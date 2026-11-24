import Foundation

struct TickerFeed: Equatable {
    let id: String
    let name: String
    let symbols: [String]
}

enum FeedCatalog {
    static let all: [TickerFeed] = [
        TickerFeed(
            id: "crypto",
            name: "Crypto",
            symbols: [
                "BTC-USD", "ETH-USD", "SOL-USD", "XRP-USD", "BNB-USD",
                "ADA-USD", "DOGE-USD", "AVAX-USD", "LINK-USD", "DOT-USD"
            ]
        ),
        TickerFeed(
            id: "nasdaq",
            name: "NASDAQ",
            symbols: [
                "^IXIC", "AAPL", "NVDA", "MSFT", "AMZN",
                "GOOGL", "META", "TSLA", "AVGO", "NFLX", "AMD"
            ]
        ),
        TickerFeed(
            id: "nyse",
            name: "NYSE",
            symbols: [
                "^NYA", "JPM", "V", "WMT", "JNJ",
                "XOM", "UNH", "HD", "PG", "MA", "BAC"
            ]
        ),
        TickerFeed(
            id: "sp500",
            name: "S&P 500",
            symbols: [
                "^GSPC", "SPY", "AAPL", "MSFT", "NVDA",
                "AMZN", "META", "BRK-B", "LLY", "JPM"
            ]
        ),
        TickerFeed(
            id: "dow",
            name: "Dow Jones",
            symbols: [
                "^DJI", "DIA", "UNH", "GS", "MSFT",
                "HD", "CAT", "SHW", "AMGN", "V"
            ]
        ),
        TickerFeed(
            id: "ftse",
            name: "FTSE 100",
            symbols: [
                "^FTSE", "AZN.L", "SHEL.L", "HSBA.L", "ULVR.L",
                "BP.L", "GSK.L", "RIO.L", "BARC.L", "LSEG.L"
            ]
        ),
        TickerFeed(
            id: "nikkei",
            name: "Nikkei 225",
            symbols: [
                "^N225", "7203.T", "6758.T", "9984.T", "6861.T",
                "8306.T", "9983.T", "8035.T", "6501.T", "7974.T"
            ]
        ),
        TickerFeed(
            id: "tsx",
            name: "TSX",
            symbols: [
                "^GSPTSE", "RY.TO", "TD.TO", "SHOP.TO", "ENB.TO",
                "CNR.TO", "BN.TO", "BMO.TO", "CP.TO", "SU.TO"
            ]
        ),
        TickerFeed(
            id: "dax",
            name: "DAX",
            symbols: [
                "^GDAXI", "SAP.DE", "SIE.DE", "ALV.DE", "DTE.DE",
                "AIR.DE", "MBG.DE", "BMW.DE", "BAS.DE", "IFX.DE"
            ]
        ),
        TickerFeed(
            id: "asx",
            name: "ASX 200",
            symbols: [
                "^AXJO", "CBA.AX", "BHP.AX", "CSL.AX", "NAB.AX",
                "WBC.AX", "ANZ.AX", "MQG.AX", "WES.AX", "TLS.AX"
            ]
        )
    ]

    static func feed(for id: String) -> TickerFeed {
        return all.first(where: { $0.id == id }) ?? all[1] // Default to NASDAQ
    }
}

final class TickerPreferences {
    static let shared = TickerPreferences()

    private let defaults = UserDefaults.standard
    private let feedKey = "TouchBarTicker.selectedFeedID"
    private let speedKey = "TouchBarTicker.scrollSpeed"

    /// Scroll speed in points per second (Touch Bar points).
    static let minSpeed: Double = 25.0
    static let maxSpeed: Double = 160.0
    static let defaultSpeed: Double = 65.0

    var selectedFeedID: String {
        get { defaults.string(forKey: feedKey) ?? "nasdaq" }
        set { defaults.set(newValue, forKey: feedKey) }
    }

    var selectedFeed: TickerFeed {
        FeedCatalog.feed(for: selectedFeedID)
    }

    var scrollSpeed: Double {
        get {
            let stored = defaults.double(forKey: speedKey)
            if stored < Self.minSpeed || stored > Self.maxSpeed {
                return Self.defaultSpeed
            }
            return stored
        }
        set {
            let clamped = min(max(newValue, Self.minSpeed), Self.maxSpeed)
            defaults.set(clamped, forKey: speedKey)
        }
    }
}
