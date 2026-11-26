#!/usr/bin/env python3
"""Run Foundation-only regression checks against extracted production flight code.

Requires Xcode/Swift. Does not call the flight provider or read account data.
Only the bundled dataset loader is adapted for the command-line environment.
This does not replace full iOS build or UI acceptance.
"""
from pathlib import Path
import json
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "Wishlist/Models/VariFlightClient.swift").read_text()
models = source[source.index("struct VariFlightLookupResult:"):source.index("struct FlightCandidatePicker:")]
methods = source[source.index("    static func candidateMatchesTripRoute("):source.index("    private func decodeMCPBody(")]
# Expose internal pure helpers only in this temporary test compilation.
methods = methods.replace("private static func", "static func")
resource = json.dumps(str(root / "Wishlist/Resources/AirportCodeCrosswalk.json"))
loader = """private static let airportCodeCrosswalk: [AirportCodeCrosswalkAirport] = {
 let data = try! Data(contentsOf: URL(fileURLWithPath: RESOURCE))
 let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
 return try! decoder.decode(AirportCodeCrosswalkFile.self, from: data).airports
}()
""".replace("RESOURCE", resource)

parser_methods = source[source.index("    private func extractFlights(from value:"):source.rfind("\n}")]
parser_harness = "\nstruct FlightParserHarness {\nfunc parse(_ value: Any) -> [VariFlightLookupResult] { extractFlights(from: value) }\n" + parser_methods + "\n}\n"

tests = r'''var checks = 0
func check(_ ok: Bool, _ name: String) { checks += 1; if !ok { print("FAIL: \(name)"); exit(1) }; print("PASS: \(name)") }
func result(_ dep: String, _ arr: String) -> VariFlightLookupResult {
 VariFlightLookupResult(airlineName: "United", departureAirport: dep, arrivalAirport: arr, departureTerminal: nil, arrivalTerminal: "7", departureTime: "16:30", estimatedArrivalTime: "18:07", baggageCarousel: nil)
}
check(FlightPresentation.providerDate("2026-11-29T21:30:00-08:00") == "2026-11-29", "candidate departure date stays in airport local date")
check(FlightPresentation.providerDate("2026-12-01 04:10:00+08:00") == "2026-12-01", "candidate arrival date survives crossing the date line")
check(FlightPresentation.providerDate("04:10") == nil, "time without date does not invent a local date")
let selected = result("乔治布什", "洛杉矶")
let date = Date(timeIntervalSince1970: 1792861200)
let saved = SavedFlightSelection(flightNumber: " ua1743 ", flightDate: date, selected: selected)
check(saved.matches(flightNumber: "UA1743", flightDate: date), "snapshot normalizes flight number")
check(!saved.matches(flightNumber: "UA1744", flightDate: date), "changed flight invalidates snapshot")
check(!saved.matches(flightNumber: "UA1743", flightDate: date.addingTimeInterval(86400)), "changed date invalidates snapshot")
let data = try JSONEncoder().encode(saved)
let read = try JSONDecoder().decode(SavedFlightSelection.self, from: data)
check(read == saved, "snapshot JSON round trip")
var legacy = try JSONSerialization.jsonObject(with: data) as! [String: Any]
legacy.removeValue(forKey: "formatVersion")
let old = try JSONDecoder().decode(SavedFlightSelection.self, from: JSONSerialization.data(withJSONObject: legacy))
check(!old.matches(flightNumber: "UA1743", flightDate: date), "legacy terminal snapshot rejected")
let aliases: [(String, Set<String>)] = [
 ("LAX", ["LAX"]), ("Los Angeles International Airport", ["LAX"]),
 ("洛杉矶", ["LAX"]), ("乔治布什", ["IAH"]),
 ("Houston", ["IAH", "HOU"]), ("New York", ["JFK", "LGA", "EWR"]),
 ("Beijing", ["PEK", "PKX"]), ("浦东机场", ["PVG"])
]
for (label, codes) in aliases { check(label == "New York" ? VariFlightClient.airportCodes(in: label).isSuperset(of: codes) : VariFlightClient.airportCodes(in: label) == codes, "airport alias: \(label)") }
check(VariFlightClient.candidateMatchesTripRoute(selected, serviceType: "接机", locationStart: "LAX Terminal 7", locationEnd: "Hotel"), "pickup matches arrival airport")
check(!VariFlightClient.candidateMatchesTripRoute(result("LAX", "SFO"), serviceType: "接机", locationStart: "LAX Terminal 7", locationEnd: "Hotel"), "pickup rejects departure-only match")
check(VariFlightClient.candidateMatchesTripRoute(result("LAX", "SFO"), serviceType: "送机", locationStart: "Hotel", locationEnd: "LAX Terminal 7"), "dropoff matches departure airport")
check(!VariFlightClient.candidateMatchesTripRoute(selected, serviceType: "送机", locationStart: "Hotel", locationEnd: "LAX Terminal 7"), "dropoff rejects arrival-only match")
check(VariFlightClient.requiresExplicitFlightChoice(serviceType: "接机", locationStart: "LAX Terminal 7", locationEnd: "Hotel"), "explicit airport requires choice")
check(VariFlightClient.explicitAirportCode(in: "123 Main Street") == nil, "ordinary address has no airport hint")
check(VariFlightClient.explicitAirportCode(in: "lax airport") == "LAX", "lowercase explicit airport code")
check(VariFlightClient.explicitAirportCode(in: "LAX Airport") == "LAX", "explicit code wins over crosswalk alias")
check(VariFlightClient.explicitAirportCode(in: "Airport sfo") == "SFO", "airport before lowercase code")
check(VariFlightClient.explicitAirportCode(in: "lax") == "LAX", "bare lowercase code")
check(VariFlightClient.explicitAirportCode(in: "Houston Airport") == nil, "ambiguous city has no single hint")
check(!VariFlightClient.airportCodes(in: "Los Angeles International Airport").contains("LOS"), "Los is not mistaken for LOS")
let parser = FlightParserHarness()
let multiLegText = "Flight details: {'code': 200, 'data': [{'fcategory': '0', 'FlightDepcode': 'HGH', 'FlightArrcode': 'TFU', 'FlightState': '提前取消'}, {'fcategory': '1', 'FlightDepcode': 'LAX', 'FlightArrcode': 'TFU', 'FlightArrtimePlanDate': '2026-12-01 08:10:00'}, {'fcategory': '1', 'FlightDepcode': 'LAX', 'FlightArrcode': 'HGH', 'FlightArrtimePlanDate': '2026-12-01 04:10:00'}]}"
let legs = parser.parse(multiLegText)
check(legs.count == 3, "provider text keeps all three records")
let laxLegs = legs.filter { $0.departureAirport == "LAX" }
check(laxLegs.compactMap(\.arrivalAirport) == ["TFU", "HGH"], "provider text keeps both LAX itineraries")
check(laxLegs.last?.estimatedArrivalTime == "2026-12-01 04:10:00", "second LAX record keeps its own arrival time")

for input: Any in [["FlightArr": "LAX", "FlightState": "延误"], "FlightArr: LAX, FlightState: 延误"] {
 check(parser.parse(input).first?.status == "延误", "provider JSON/text status parsed")
}
check(parser.parse(["FlightArr": "LAX"]).first?.status == nil, "missing provider status stays missing")
let locales = ["zh-Hans", "zh-Hant", "en", "es", "ja", "ko"].map(Locale.init(identifier:))
for locale in locales {
 check(!FlightPresentation.status("延误", locale: locale).isEmpty, "status localized: \(locale.identifier)")
 check(FlightPresentation.status(nil, locale: locale) != FlightPresentation.status("计划", locale: locale), "missing status is not scheduled: \(locale.identifier)")
 check(FlightPresentation.name("LAX", kind: "airport", locale: locale) != "LAX", "airport localized: \(locale.identifier)")
}
check(FlightPresentation.status("landed", locale: Locale(identifier: "en")) == "Landed", "landed status")
check(FlightPresentation.status("4", locale: Locale(identifier: "en")) == "Status unavailable", "unverified numeric enum is not guessed")
check(FlightPresentation.name("Tokyo", kind: "airport", locale: Locale(identifier: "ja")) == "Tokyo", "ambiguous city preserved")
check(FlightPresentation.name("Unknown Carrier", kind: "airline", locale: Locale(identifier: "es")) == "Unknown Carrier", "unknown airline preserved")
check(FlightPresentation.name("长荣航空股份有限公司", kind: "airline", locale: Locale(identifier: "en")) == "EVA Air", "provider airline alias")
check(read.selected.status == nil, "legacy snapshot without status decodes")
var live = selected; live.status = "延误"
let liveRead = try JSONDecoder().decode(VariFlightLookupResult.self, from: JSONEncoder().encode(live))
check(liveRead.status == "延误", "raw status snapshot round trip")
let jx2Payload = ["FlightDepcode": "TPE", "FlightArrcode": "LAX",
    "FlightDeptimePlanDate": "2026-11-25 23:40:00", "FlightDeptimeDate": "2026-11-26 00:12:00",
    "FlightArrtimePlanDate": "2026-11-25 19:05:00", "FlightArrtimeReadyDate": "2026-11-25 18:58:00"]
let jx2 = parser.parse(jx2Payload)[0]
check(jx2.displayDeparture.time == "2026-11-26 00:12:00" && jx2.displayDeparture.label == "实际起飞", "JX2 actual departure crosses midnight")
check(jx2.displayArrival.time == "2026-11-25 18:58:00" && jx2.displayArrival.label == "预计到达时间", "JX2 estimated arrival supersedes schedule")
check(jx2.departureTime == "2026-11-25 23:40:00", "scheduled departure remains available for the original flight date")
let jx2Text = jx2Payload.map { "'\($0.key)': '\($0.value)'" }.joined(separator: ", ")
check(parser.parse("{\(jx2Text)}").first?.displayArrival.time == jx2.displayArrival.time, "MCP text also uses the estimated arrival")
check(parser.parse(["FlightArrtimePlanDate": "19:05", "FlightArrtimeReadyDate": "--"]).first?.displayArrival.label == "计划到达", "scheduled arrival is explicitly labeled when estimate is missing")
print("TOTAL: \(checks) passed")
'''

with tempfile.TemporaryDirectory(prefix="trvelma-flight-check-") as temporary:
    target = Path(temporary) / "flight-check.swift"
    target.write_text("import Foundation\nimport CoreFoundation\n" + models + "\nstruct VariFlightClient {\n" + loader + methods + "\n}\n" + parser_harness + tests)
    subprocess.run(["swift", str(target)], check=True)
