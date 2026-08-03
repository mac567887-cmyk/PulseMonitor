import Foundation
import Network
import Observation

/// Optional local-only HTTP dashboard for LAN viewing.
/// Requires an explicit token — never binds without authentication.
@MainActor
@Observable
public final class WebDashboardServer {
    public private(set) var isRunning = false
    public private(set) var port: UInt16 = 8742
    public private(set) var token: String
    public private(set) var lastError: String?
    public var bindAddressDescription: String { "http://127.0.0.1:\(port)/?token=\(token)" }

    private var listener: NWListener?
    private weak var collector: MetricsCollector?
    private var connections: [NWConnection] = []

    public init() {
        if let existing = UserDefaults.standard.string(forKey: "v3.webDashboard.token"), !existing.isEmpty {
            token = existing
        } else {
            token = String(UUID().uuidString.prefix(8))
            UserDefaults.standard.set(token, forKey: "v3.webDashboard.token")
        }
    }

    public func bind(collector: MetricsCollector) {
        self.collector = collector
    }

    public func start(port: UInt16 = 8742) {
        stop()
        self.port = port
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        self?.lastError = nil
                    case .failed(let error):
                        self?.lastError = error.localizedDescription
                        self?.isRunning = false
                    case .cancelled:
                        self?.isRunning = false
                    default:
                        break
                    }
                }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            lastError = error.localizedDescription
            isRunning = false
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
        isRunning = false
    }

    public func rotateToken() {
        token = String(UUID().uuidString.prefix(8))
        UserDefaults.standard.set(token, forKey: "v3.webDashboard.token")
    }

    private func accept(_ connection: NWConnection) {
        connections.append(connection)
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] data, _, _, _ in
            Task { @MainActor in
                guard let self else { return }
                let request = String(data: data ?? Data(), encoding: .utf8) ?? ""
                let response = self.response(for: request)
                connection.send(content: response, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }

    private func response(for request: String) -> Data {
        let authorized = request.contains("token=\(token)") || request.contains("Authorization: Bearer \(token)")
        guard authorized else {
            return http(status: "401 Unauthorized", body: "Authentication required. Append ?token=… to the URL.", contentType: "text/plain")
        }

        if request.contains("GET /api/metrics") {
            let payload = apiPayload()
            return http(status: "200 OK", body: payload, contentType: "application/json")
        }

        let html = htmlPage()
        return http(status: "200 OK", body: html, contentType: "text/html; charset=utf-8")
    }

    private func apiPayload() -> String {
        guard let metrics = collector?.latestMetrics else {
            return #"{"error":"no samples yet"}"#
        }
        let gpu = metrics.gpu.utilization.map { String(format: "%.1f", $0) } ?? "null"
        return """
        {"cpu":\(String(format: "%.1f", metrics.cpu.totalUsage)),"gpu":\(gpu),"memory":\(String(format: "%.1f", metrics.memory.usagePercent)),"thermal":"\(metrics.thermal.thermalState.rawValue)","timestamp":\(Int(metrics.timestamp.timeIntervalSince1970))}
        """
    }

    private func htmlPage() -> String {
        """
        <!doctype html>
        <html><head><meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/>
        <title>PulseMonitor</title>
        <style>
        body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;background:#0b0d12;color:#e8eefc;margin:0;padding:24px}
        .card{background:#161b26;border-radius:16px;padding:20px;margin:12px 0;box-shadow:0 10px 30px rgba(0,0,0,.35)}
        h1{margin:0 0 8px} .muted{opacity:.65} .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(140px,1fr));gap:12px}
        .metric{font-size:28px;font-variant-numeric:tabular-nums}
        </style></head><body>
        <h1>PulseMonitor</h1>
        <p class="muted">Local dashboard · refreshes every 2s · token required</p>
        <div class="grid">
          <div class="card"><div class="muted">CPU</div><div class="metric" id="cpu">—</div></div>
          <div class="card"><div class="muted">GPU</div><div class="metric" id="gpu">—</div></div>
          <div class="card"><div class="muted">Memory</div><div class="metric" id="mem">—</div></div>
          <div class="card"><div class="muted">Thermal</div><div class="metric" id="therm">—</div></div>
        </div>
        <script>
        const token = new URLSearchParams(location.search).get('token') || '';
        async function tick(){
          try{
            const r = await fetch('/api/metrics?token='+encodeURIComponent(token));
            if(!r.ok){document.getElementById('cpu').textContent='auth';return;}
            const j = await r.json();
            document.getElementById('cpu').textContent = j.cpu.toFixed(0)+'%';
            document.getElementById('gpu').textContent = (j.gpu==null?'—':j.gpu.toFixed(0)+'%');
            document.getElementById('mem').textContent = j.memory.toFixed(0)+'%';
            document.getElementById('therm').textContent = j.thermal;
          }catch(e){}
        }
        tick(); setInterval(tick, 2000);
        </script></body></html>
        """
    }

    private func http(status: String, body: String, contentType: String) -> Data {
        let payload = Data(body.utf8)
        let header = """
        HTTP/1.1 \(status)\r
        Content-Type: \(contentType)\r
        Content-Length: \(payload.count)\r
        Connection: close\r
        Access-Control-Allow-Origin: *\r
        \r

        """
        var data = Data(header.utf8)
        data.append(payload)
        return data
    }
}
