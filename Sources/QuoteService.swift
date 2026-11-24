import Foundation

struct StockQuote: Equatable {
    let symbol: String
    let displaySymbol: String
    let price: Double
    let changePercent: Double
    let currency: String

    var formattedPrice: String {
        let prefix = Self.currencyPrefix(for: currency, isIndex: symbol.hasPrefix("^"))
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true

        if price < 1.0 {
            formatter.minimumFractionDigits = 4
            formatter.maximumFractionDigits = 4
        } else if price >= 10000.0 {
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 0
        } else {
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
        }

        let numStr = formatter.string(from: NSNumber(value: price)) ?? String(format: "%.2f", price)
        return "\(prefix)\(numStr)"
    }

    var formattedChange: String {
        let sign = changePercent > 0 ? "+" : ""
        return String(format: "%@%.2f%%", sign, changePercent)
    }

    private static func currencyPrefix(for code: String, isIndex: Bool) -> String {
        if isIndex { return "" }
        if code == "GBp" { return "p" }
        switch code.uppercased() {
        case "USD": return "$"
        case "EUR": return "€"
        case "GBP": return "£"
        case "JPY": return "¥"
        case "CAD": return "C$"
        case "AUD": return "A$"
        default: return ""
        }
    }

    static func cleanDisplayName(for rawSymbol: String) -> String {
        let indexNames: [String: String] = [
            "^IXIC": "NASDAQ",
            "^NYA": "NYSE",
            "^GSPC": "S&P 500",
            "^DJI": "DOW",
            "^FTSE": "FTSE",
            "^N225": "NIKKEI",
            "^GSPTSE": "TSX",
            "^GDAXI": "DAX",
            "^AXJO": "ASX"
        ]
        if let mapped = indexNames[rawSymbol] {
            return mapped
        }
        if rawSymbol.hasSuffix("-USD") {
            return String(rawSymbol.dropLast(4))
        }
        for suffix in [".L", ".T", ".TO", ".DE", ".AX"] {
            if rawSymbol.hasSuffix(suffix) {
                return String(rawSymbol.dropLast(suffix.count))
            }
        }
        return rawSymbol
    }
}

final class QuoteService {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            "Accept": "application/json"
        ]
        self.session = URLSession(configuration: config)
    }

    func fetchQuotes(for symbols: [String], completion: @escaping ([StockQuote]) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var resultsBySymbol: [String: StockQuote] = [:]

        for symbol in symbols {
            group.enter()
            fetchSingleQuote(symbol: symbol) { quote in
                if let quote = quote {
                    lock.lock()
                    resultsBySymbol[symbol] = quote
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            let ordered = symbols.compactMap { resultsBySymbol[$0] }
            completion(ordered)
        }
    }

    private func fetchSingleQuote(symbol: String, completion: @escaping (StockQuote?) -> Void) {
        guard let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?interval=1d&range=1d") else {
            completion(nil)
            return
        }

        session.dataTask(with: url) { data, response, error in
            guard error == nil,
                  let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let data = data else {
                completion(nil)
                return
            }

            let quote = Self.parseYahooChart(data: data, requestedSymbol: symbol)
            completion(quote)
        }.resume()
    }

    static func parseYahooChart(data: Data, requestedSymbol: String) -> StockQuote? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chart = json["chart"] as? [String: Any],
              let results = chart["result"] as? [[String: Any]],
              let first = results.first,
              let meta = first["meta"] as? [String: Any],
              let price = meta["regularMarketPrice"] as? Double else {
            return nil
        }

        let prevClose = (meta["chartPreviousClose"] as? Double)
            ?? (meta["previousClose"] as? Double)
            ?? price

        let changePct: Double
        if prevClose > 0 {
            changePct = ((price - prevClose) / prevClose) * 100.0
        } else {
            changePct = 0.0
        }

        let currency = (meta["currency"] as? String) ?? "USD"
        let display = StockQuote.cleanDisplayName(for: requestedSymbol)

        return StockQuote(
            symbol: requestedSymbol,
            displaySymbol: display,
            price: price,
            changePercent: changePct,
            currency: currency
        )
    }
}
