#!/usr/bin/env python3
"""Builds avd-sessionhosts-monitoring-2.0.workbook.json.

The workbook is plain JSON. This script only exists so the queries stay readable
and so every tab is generated from the same template.
"""
import json, uuid, pathlib

WS = "microsoft.operationalinsights/workspaces"
PREAMBLE = """let hosts = dynamic([{SessionHosts}]);
let shortName = (s:string) { tolower(tostring(split(s, ".")[0])) };
"""

def uid():
    return str(uuid.uuid4())

def text(md, name):
    return {"type": 1, "content": {"json": md}, "name": name}

def query(title, kql, name, visualization="table", size=0, height=None, no_time_param=False):
    content = {
        "version": "KqlItem/1.0",
        "query": kql,
        "size": size,
        "title": title,
        "queryType": 0,
        "resourceType": WS,
        "crossComponentResources": ["{Workspace}"],
        "visualization": visualization,
    }
    if not no_time_param:
        content["timeContextFromParameter"] = "TimeRange"
    else:
        content["timeContext"] = {"durationMs": 86400000}
    if height:
        content["height"] = height
    return {"type": 3, "content": content, "name": name}

def group(tab_value, items, name):
    return {
        "type": 12,
        "conditionalVisibility": {"parameterName": "SelectedTab", "comparison": "isEqualTo", "value": tab_value},
        "content": {"version": "NotebookGroup/1.0", "groupType": "editable", "items": items},
        "name": name,
    }

# ---------------------------------------------------------------- parameters
parameters = {
    "type": 9,
    "content": {
        "version": "KqlParameterItem/1.0",
        "parameters": [
            {
                "id": uid(), "version": "KqlParameterItem/1.0", "name": "Workspace",
                "label": "Log Analytics workspace", "type": 5, "isRequired": True,
                "multiSelect": False, "quote": "'", "delimiter": ",",
                "typeSettings": {"additionalResourceOptions": [], "resourceTypeFilter": {WS: True}},
                "timeContext": {"durationMs": 86400000},
            },
            {
                "id": uid(), "version": "KqlParameterItem/1.0", "name": "TimeRange",
                "label": "Time range", "type": 4, "isRequired": True,
                "value": {"durationMs": 86400000},
                "typeSettings": {"selectableValues": [
                    {"durationMs": 3600000}, {"durationMs": 14400000}, {"durationMs": 43200000},
                    {"durationMs": 86400000}, {"durationMs": 172800000}, {"durationMs": 604800000},
                    {"durationMs": 2592000000},
                ]},
            },
            {
                "id": uid(), "version": "KqlParameterItem/1.0", "name": "HostPool",
                "label": "Host pool", "type": 2, "isRequired": True, "multiSelect": True,
                "quote": "'", "delimiter": ",",
                "query": (
                    "desktopvirtualizationresources\n"
                    "| where type =~ 'microsoft.desktopvirtualization/hostpools'\n"
                    "| project value = tolower(name), label = name\n"
                    "| order by label asc"
                ),
                "crossComponentResources": ["value::all"],
                "typeSettings": {"additionalResourceOptions": ["value::all"], "showDefault": False},
                "queryType": 1, "resourceType": "microsoft.resourcegraph/resources",
                "value": ["value::all"],
            },
            {
                "id": uid(), "version": "KqlParameterItem/1.0", "name": "SessionHosts",
                "label": "Session hosts", "type": 2, "isRequired": False, "multiSelect": True,
                "quote": "'", "delimiter": ",",
                "description": "Leave on All to include every session host in the selected host pools.",
                "query": (
                    "desktopvirtualizationresources\n"
                    "| where type =~ 'microsoft.desktopvirtualization/hostpools/sessionhosts'\n"
                    "| extend hostPool = tolower(tostring(split(id, '/')[8]))\n"
                    "| where '*' in ({HostPool}) or hostPool in ({HostPool})\n"
                    "| extend sessionHost = tostring(split(name, '/')[1])\n"
                    "| project value = tolower(tostring(split(sessionHost, '.')[0])), label = sessionHost\n"
                    "| order by label asc"
                ),
                "crossComponentResources": ["value::all"],
                "typeSettings": {"additionalResourceOptions": ["value::all"], "showDefault": False},
                "queryType": 1, "resourceType": "microsoft.resourcegraph/resources",
                "value": ["value::all"],
            },
        ],
        "style": "pills", "queryType": 0, "resourceType": WS,
    },
    "name": "parameters",
}

TABS = [
    ("overview", "Overview"),
    ("health", "Session host health"),
    ("capacity", "Capacity & density"),
    ("experience", "User experience"),
    ("connections", "Connections & errors"),
    ("fslogix", "FSLogix"),
    ("quality", "Data quality"),
]

tabs_item = {
    "type": 11,
    "content": {
        "version": "LinkItem/1.0", "style": "tabs",
        "links": [
            {"id": uid(), "cellValue": "SelectedTab", "linkTarget": "parameter",
             "linkLabel": label, "subTarget": value, "style": "link"}
            for value, label in TABS
        ],
    },
    "name": "tabs",
}

# ------------------------------------------------------------------ queries
Q_OVERVIEW_TILES = PREAMBLE + """let health = WVDAgentHealthStatus
| extend Host = shortName(SessionHostName)
| where array_length(hosts) == 0 or "*" in (hosts) or Host in (hosts)
| summarize arg_max(TimeGenerated, Status) by Host;
let sessions = Perf
| where ObjectName == "Terminal Services" and CounterName == "Active Sessions"
| extend Host = shortName(Computer)
| where array_length(hosts) == 0 or "*" in (hosts) or Host in (hosts)
| summarize Sessions = max(CounterValue) by Host, bin(TimeGenerated, 15m)
| summarize Sessions = max(Sessions) by bin_at(TimeGenerated, 15m, now())
| top 1 by TimeGenerated desc;
let delay = Perf
| where ObjectName == "User Input Delay per Session" and CounterName == "Max Input Delay"
| where InstanceName !in ("Max", "Average")
| extend Host = shortName(Computer)
| where array_length(hosts) == 0 or "*" in (hosts) or Host in (hosts)
| summarize P95 = percentile(CounterValue, 95);
let connections = WVDConnections
| summarize States = make_set(State) by CorrelationId
| summarize Attempts = count(), Succeeded = countif(set_has_element(States, "Connected"));
union
(health | summarize Metric = "Session hosts", Value = todouble(count()), Unit = "hosts"),
(health | summarize Metric = "Available", Value = todouble(countif(Status == "Available")), Unit = "hosts"),
(health | summarize Metric = "Need attention", Value = todouble(countif(Status != "Available")), Unit = "hosts"),
(sessions | summarize Metric = "Active sessions", Value = todouble(max(Sessions)), Unit = "sessions"),
(delay | summarize Metric = "Input delay P95", Value = round(max(P95)), Unit = "ms"),
(connections | summarize Metric = "Connection success", Value = round(100.0 * max(Succeeded) / max(Attempts), 1), Unit = "%")
"""

Q_OVERVIEW_TABLE = PREAMBLE + """let health = WVDAgentHealthStatus
| extend Host = shortName(SessionHostName)
| where array_length(hosts) == 0 or "*" in (hosts) or Host in (hosts)
| summarize arg_max(TimeGenerated, Status, AgentVersion, SessionHostHealthCheckResult) by Host;
let perf = Perf
| extend Host = shortName(Computer)
| where array_length(hosts) == 0 or "*" in (hosts) or Host in (hosts)
| summarize
    CpuAvg = avgif(CounterValue, ObjectName == "Processor Information" and CounterName == "% Processor Time" and InstanceName == "_Total"),
    Sessions = maxif(CounterValue, ObjectName == "Terminal Services" and CounterName == "Active Sessions"),
    MemoryUsedPct = avgif(CounterValue, ObjectName == "Memory" and CounterName =~ "% Committed Bytes In Use")
    by Host;
let delay = Perf
| where ObjectName == "User Input Delay per Session" and CounterName == "Max Input Delay"
| where InstanceName !in ("Max", "Average")
| extend Host = shortName(Computer)
| summarize InputDelayP95 = percentile(CounterValue, 95) by Host;
health
| join kind=leftouter perf on Host
| join kind=leftouter delay on Host
| extend FailedChecks = tostring(array_length(parse_json(SessionHostHealthCheckResult)))
| project
    ["Session host"] = Host,
    Status,
    Sessions = tolong(Sessions),
    ["CPU avg %"] = round(CpuAvg, 1),
    ["Memory used %"] = round(MemoryUsedPct, 1),
    ["Input delay P95 (ms)"] = round(InputDelayP95),
    ["Agent version"] = AgentVersion,
    ["Last report"] = TimeGenerated
| order by Status asc, ["Input delay P95 (ms)"] desc
"""

Q_HEALTH_HEATMAP = PREAMBLE + """WVDAgentHealthStatus
| extend Host = shortName(SessionHostName)
| where array_length(hosts) == 0 or "*" in (hosts) or Host in (hosts)
| summarize Unhealthy = countif(Status != "Available"), Reports = count() by Host, bin(TimeGenerated, 1h)
| extend UnhealthyPct = round(100.0 * Unhealthy / Reports, 1)
| project TimeGenerated, Host, UnhealthyPct
| evaluate pivot(Host, max(UnhealthyPct))
| order by TimeGenerated asc
"""

Q_HEALTH_CHECKS = PREAMBLE + """WVDAgentHealthStatus
| extend Host = shortName(SessionHostName)
| where array_length(hosts) == 0 or "*" in (hosts) or Host in (hosts)
| where Status != "Available"
| mv-expand Check = parse_json(SessionHostHealthCheckResult)
| extend HealthCheck = tostring(Check.HealthCheckName), Result = tostring(Check.HealthCheckResult)
| where Result != "HealthCheckSucceeded"
| summarize Failures = count(), LastSeen = max(TimeGenerated) by ["Session host"] = Host, HealthCheck, Result
| order by LastSeen desc
"""

Q_CAPACITY_DENSITY = PREAMBLE + """let cpu = Perf
| where ObjectName == "Processor Information" and CounterName == "% Processor Time" and InstanceName == "_Total"
| extend Host = shortName(Computer)
| where array_length(hosts) == 0 or "*" in (hosts) or Host in (hosts)
| summarize CpuP95 = percentile(CounterValue, 95) by Host, bin(TimeGenerated, 1h);
let sessions = Perf
| where ObjectName == "Terminal Services" and CounterName == "Active Sessions"
| extend Host = shortName(Computer)
| summarize Sessions = max(CounterValue) by Host, bin(TimeGenerated, 1h);
cpu
| join kind=inner sessions on Host, TimeGenerated
| where Sessions > 0
| extend CpuPerSession = CpuP95 / Sessions
| summarize
    ["CPU per session %"] = round(avg(CpuPerSession), 1),
    ["Peak sessions"] = tolong(max(Sessions)),
    ["Peak CPU P95 %"] = round(max(CpuP95), 1)
    by ["Session host"] = Host
| order by ["CPU per session %"] desc
"""

Q_CAPACITY_TREND = PREAMBLE + """Perf
| where ObjectName == "Terminal Services" and CounterName == "Active Sessions"
| extend Host = shortName(Computer)
| where array_length(hosts) == 0 or "*" in (hosts) or Host in (hosts)
| summarize Sessions = max(CounterValue) by Host, bin(TimeGenerated, 15m)
| summarize ["Active sessions"] = sum(Sessions) by TimeGenerated
| order by TimeGenerated asc
"""

Q_EXPERIENCE_DELAY = PREAMBLE + """Perf
| where ObjectName == "User Input Delay per Session" and CounterName == "Max Input Delay"
| where InstanceName !in ("Max", "Average")
| extend Host = shortName(Computer)
| where array_length(hosts) == 0 or "*" in (hosts) or Host in (hosts)
| summarize P50 = percentile(CounterValue, 50), P95 = percentile(CounterValue, 95) by bin(TimeGenerated, 15m)
| order by TimeGenerated asc
"""

Q_EXPERIENCE_HOSTS = PREAMBLE + """Perf
| where ObjectName == "User Input Delay per Session" and CounterName == "Max Input Delay"
| where InstanceName !in ("Max", "Average")
| extend Host = shortName(Computer)
| where array_length(hosts) == 0 or "*" in (hosts) or Host in (hosts)
| summarize
    ["Input delay P50 (ms)"] = round(percentile(CounterValue, 50)),
    ["Input delay P95 (ms)"] = round(percentile(CounterValue, 95)),
    ["Input delay max (ms)"] = round(max(CounterValue))
    by ["Session host"] = Host
| order by ["Input delay P95 (ms)"] desc
"""

Q_EXPERIENCE_NETWORK = PREAMBLE + """WVDConnectionNetworkData
| join kind=inner (
    WVDConnections
    | where State == "Connected"
    | project CorrelationId, SessionHostName, TransportType
  ) on CorrelationId
| extend Host = shortName(SessionHostName)
| where array_length(hosts) == 0 or "*" in (hosts) or Host in (hosts)
| summarize
    ["RTT P50 (ms)"] = round(percentile(EstRoundTripTimeInMs, 50)),
    ["RTT P95 (ms)"] = round(percentile(EstRoundTripTimeInMs, 95)),
    ["Bandwidth P50 (KBps)"] = round(percentile(EstAvailableBandwidthKBps, 50)),
    Measurements = count()
    by ["Session host"] = Host, TransportType
| order by ["RTT P95 (ms)"] desc
"""

Q_CONNECTIONS_SUCCESS = PREAMBLE + """WVDConnections
| summarize States = make_set(State), SessionHostName = take_any(SessionHostName) by CorrelationId
| extend Succeeded = set_has_element(States, "Connected")
| extend Host = iff(isempty(SessionHostName), "(no host assigned)", shortName(SessionHostName))
| where array_length(hosts) == 0 or "*" in (hosts) or Host in (hosts) or Host == "(no host assigned)"
| summarize Attempts = count(), Failed = countif(not(Succeeded)) by ["Session host"] = Host
| extend ["Success rate %"] = round(100.0 * (Attempts - Failed) / Attempts, 1)
| order by ["Success rate %"] asc
"""

Q_CONNECTIONS_ERRORS = """WVDErrors
| summarize Errors = count(), LastSeen = max(TimeGenerated), Example = take_any(Message)
    by CodeSymbolic, Source, ServiceError
| order by Errors desc
"""

Q_FSLOGIX = PREAMBLE + """Event
| where EventLog startswith "Microsoft-FSLogix-Apps"
| extend Host = shortName(Computer)
| where array_length(hosts) == 0 or "*" in (hosts) or Host in (hosts)
| where EventLevelName in ("Error", "Warning")
| summarize Events = count(), LastSeen = max(TimeGenerated), Example = take_any(RenderedDescription)
    by ["Session host"] = Host, EventLog, EventID, EventLevelName
| order by Events desc
"""

Q_QUALITY_SOURCES = """union withsource=Table Perf, Event, WVDAgentHealthStatus, WVDConnections, WVDConnectionNetworkData
| extend Source = coalesce(ObjectName, EventLog, Table)
| summarize Records = count(), LastRecord = max(TimeGenerated) by Table, Source, CounterName
| extend ["Minutes old"] = datetime_diff("minute", now(), LastRecord)
| order by Table asc, Source asc
"""

Q_QUALITY_HEARTBEAT = PREAMBLE + """Heartbeat
| extend Host = shortName(Computer)
| where array_length(hosts) == 0 or "*" in (hosts) or Host in (hosts)
| summarize LastHeartbeat = max(TimeGenerated), Rules = make_set(Category) by ["Session host"] = Host
| extend ["Minutes old"] = datetime_diff("minute", now(), LastHeartbeat)
| order by ["Minutes old"] desc
"""

Q_QUALITY_SILENT = PREAMBLE + """let reporting = union
    (Perf | extend Host = shortName(Computer) | distinct Host),
    (Heartbeat | extend Host = shortName(Computer) | distinct Host);
print Host = hosts
| mv-expand Host to typeof(string)
| where Host != "*"
| join kind=leftanti reporting on Host
| project ["Session host without data"] = Host
"""

intro = text(
    "AVD Sessionhosts Monitoring 2.0. Select a workspace, one or more host pools and a time range. "
    "The Data quality tab shows whether every source this workbook depends on is delivering data.",
    "intro",
)

items = [
    text("# AVD Sessionhosts Monitoring 2.0", "title"),
    intro,
    parameters,
    tabs_item,
    group("overview", [
        query("Summary", Q_OVERVIEW_TILES, "overview-tiles", "tiles", size=4),
        query("Session hosts", Q_OVERVIEW_TABLE, "overview-table", "table", size=0),
    ], "group-overview"),
    group("health", [
        query("Unhealthy reports per hour (%)", Q_HEALTH_HEATMAP, "health-heatmap", "timechart", size=0),
        query("Failed health checks", Q_HEALTH_CHECKS, "health-checks", "table", size=0),
    ], "group-health"),
    group("capacity", [
        query("Cost per session", Q_CAPACITY_DENSITY, "capacity-density", "table", size=0),
        query("Active sessions", Q_CAPACITY_TREND, "capacity-trend", "timechart", size=0),
    ], "group-capacity"),
    group("experience", [
        query("Input delay over time (ms)", Q_EXPERIENCE_DELAY, "experience-delay", "timechart", size=0),
        query("Input delay per session host", Q_EXPERIENCE_HOSTS, "experience-hosts", "table", size=0),
        query("Round trip time and bandwidth", Q_EXPERIENCE_NETWORK, "experience-network", "table", size=0),
    ], "group-experience"),
    group("connections", [
        query("Connection success per session host", Q_CONNECTIONS_SUCCESS, "connections-success", "table", size=0),
        query("Errors", Q_CONNECTIONS_ERRORS, "connections-errors", "table", size=0),
    ], "group-connections"),
    group("fslogix", [
        query("FSLogix errors and warnings", Q_FSLOGIX, "fslogix-events", "table", size=0),
    ], "group-fslogix"),
    group("quality", [
        query("Sources and freshness", Q_QUALITY_SOURCES, "quality-sources", "table", size=0),
        query("Heartbeat per session host", Q_QUALITY_HEARTBEAT, "quality-heartbeat", "table", size=0),
        query("Session hosts without data", Q_QUALITY_SILENT, "quality-silent", "table", size=0),
    ], "group-quality"),
]

workbook = {
    "version": "Notebook/1.0",
    "items": items,
    "isLocked": False,
    "fallbackResourceIds": ["Azure Monitor"],
    "$schema": "https://github.com/Microsoft/Application-Insights-Workbooks/blob/master/schema/workbook.json",
}

out = pathlib.Path(__file__).with_name("avd-sessionhosts-monitoring-2.0.workbook.json")
out.write_text(json.dumps(workbook, indent=2) + "\n", encoding="utf-8")
print(f"written {out} ({out.stat().st_size} bytes)")
