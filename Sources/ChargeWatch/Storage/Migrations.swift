import Foundation

enum Migrations {
    static let schemas: [String] = [
        """
        CREATE TABLE IF NOT EXISTS samples_raw (
          ts INTEGER PRIMARY KEY,
          is_charging INTEGER NOT NULL,
          external_connected INTEGER NOT NULL,
          has_battery INTEGER NOT NULL,
          battery_watts REAL NOT NULL,
          adapter_watts REAL,
          system_load_watts REAL,
          voltage_mv INTEGER,
          amperage_ma INTEGER,
          soc_percent INTEGER,
          adapter_max_watts INTEGER,
          adapter_desc TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_raw_ts ON samples_raw(ts);
        """,
        """
        CREATE TABLE IF NOT EXISTS samples_10s (
          ts INTEGER PRIMARY KEY,
          battery_watts REAL NOT NULL,
          adapter_watts REAL,
          system_load_watts REAL,
          soc_percent INTEGER,
          is_charging INTEGER NOT NULL,
          external_connected INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_10s_ts ON samples_10s(ts);
        """,
        """
        CREATE TABLE IF NOT EXISTS samples_1min (
          ts INTEGER PRIMARY KEY,
          battery_watts REAL NOT NULL,
          adapter_watts REAL,
          system_load_watts REAL,
          soc_percent INTEGER,
          is_charging INTEGER NOT NULL,
          external_connected INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_1min_ts ON samples_1min(ts);
        """,
        """
        CREATE TABLE IF NOT EXISTS samples_5min (
          ts INTEGER PRIMARY KEY,
          battery_watts REAL NOT NULL,
          adapter_watts REAL,
          system_load_watts REAL,
          soc_percent INTEGER,
          is_charging INTEGER NOT NULL,
          external_connected INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_5min_ts ON samples_5min(ts);
        """
    ]

    static func run(on db: Database) throws {
        for sql in schemas { try db.exec(sql) }
    }
}
