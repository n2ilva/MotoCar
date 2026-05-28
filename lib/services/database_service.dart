import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/driver_settings.dart';
import '../models/offer.dart';

class DatabaseService {
  static const retentionDays = 15;
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final dbPath = join(await getDatabasesPath(), 'motocar.db');
    _database = await openDatabase(
      dbPath,
      version: 4,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE settings (
            id INTEGER PRIMARY KEY,
            max_pickup_km REAL NOT NULL,
            max_destination_km REAL NOT NULL,
            min_profit_km REAL NOT NULL,
            gasoline_price REAL NOT NULL,
            ethanol_price REAL NOT NULL,
            gasoline_consumption REAL NOT NULL,
            ethanol_consumption REAL NOT NULL,
            other_cost_km REAL NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE offers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            platform TEXT NOT NULL,
            fare REAL NOT NULL,
            pickup_km REAL NOT NULL,
            destination_km REAL NOT NULL,
            detected_at TEXT NOT NULL,
            is_worthwhile INTEGER NOT NULL,
            source TEXT NOT NULL,
            raw_text TEXT NOT NULL,
            accepted_at TEXT,
            completed_at TEXT
          )
        ''');
        await _createOfferUniquenessIndex(db);
        await db.insert('settings', const DriverSettings().toMap());
      },
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE offers ADD COLUMN accepted_at TEXT');
          await db.execute('ALTER TABLE offers ADD COLUMN completed_at TEXT');
        }
        if (oldVersion < 3) {
          await _mergeDuplicateOffers(db);
          await _createOfferUniquenessIndex(db);
        }
        if (oldVersion < 4) {
          await db.execute('DROP TABLE IF EXISTS tracking_sessions');
        }
      },
    );
    return _database!;
  }

  Future<DriverSettings> loadSettings() async {
    final db = await database;
    final rows = await db.query('settings', where: 'id = 1');
    if (rows.isEmpty) {
      const defaults = DriverSettings();
      await db.insert(
        'settings',
        defaults.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return defaults;
    }
    return DriverSettings.fromMap(rows.single);
  }

  Future<void> saveSettings(DriverSettings settings) async {
    final db = await database;
    await db.insert(
      'settings',
      settings.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> insertOffer(RideOffer offer) async {
    final db = await database;
    await _purgeExpiredData(db);
    final map = offer.toMap()..remove('id');
    final id = await db.insert(
      'offers',
      map,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return id != 0;
  }

  Future<List<RideOffer>> loadOffers() async {
    final db = await database;
    await _purgeExpiredData(db);
    final rows = await db.query('offers', orderBy: 'detected_at DESC');
    return rows.map(RideOffer.fromMap).toList();
  }

  Future<void> markAccepted(RideOffer offer, DateTime acceptedAt) async {
    final db = await database;
    await _purgeExpiredData(db);
    final id = await _matchingOfferId(db, offer, onlyAccepted: false);
    if (id != null) {
      await db.update(
        'offers',
        {'accepted_at': acceptedAt.toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<void> markCompleted(RideOffer offer, DateTime completedAt) async {
    final db = await database;
    await _purgeExpiredData(db);
    final id = await _matchingOfferId(db, offer, onlyAccepted: true);
    if (id != null) {
      await db.update(
        'offers',
        {'completed_at': completedAt.toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<int?> _matchingOfferId(
    Database db,
    RideOffer offer, {
    required bool onlyAccepted,
  }) async {
    final acceptedClause = onlyAccepted ? ' AND accepted_at IS NOT NULL' : '';
    final rows = await db.query(
      'offers',
      columns: ['id'],
      where:
          'platform = ? AND fare = ? AND pickup_km = ? AND destination_km = ?'
          '$acceptedClause',
      whereArgs: [
        offer.platform.name,
        offer.fare,
        offer.pickupKm,
        offer.destinationKm,
      ],
      orderBy: 'detected_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['id'] as int;
  }

  static Future<void> _createOfferUniquenessIndex(Database db) async {
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS offers_unique_request
      ON offers (platform, fare, pickup_km, destination_km)
    ''');
  }

  static Future<void> _mergeDuplicateOffers(Database db) async {
    await db.execute('''
      UPDATE offers
      SET accepted_at = (
        SELECT MAX(duplicate.accepted_at)
        FROM offers duplicate
        WHERE duplicate.platform = offers.platform
          AND duplicate.fare = offers.fare
          AND duplicate.pickup_km = offers.pickup_km
          AND duplicate.destination_km = offers.destination_km
      ),
      completed_at = (
        SELECT MAX(duplicate.completed_at)
        FROM offers duplicate
        WHERE duplicate.platform = offers.platform
          AND duplicate.fare = offers.fare
          AND duplicate.pickup_km = offers.pickup_km
          AND duplicate.destination_km = offers.destination_km
      )
      WHERE id IN (
        SELECT MIN(id)
        FROM offers
        GROUP BY platform, fare, pickup_km, destination_km
      )
    ''');
    await db.execute('''
      DELETE FROM offers
      WHERE id NOT IN (
        SELECT MIN(id)
        FROM offers
        GROUP BY platform, fare, pickup_km, destination_km
      )
    ''');
  }

  static Future<void> _purgeExpiredData(Database db) async {
    final cutoff = DateTime.now()
        .subtract(const Duration(days: retentionDays))
        .toIso8601String();
    await db.delete('offers', where: 'detected_at < ?', whereArgs: [cutoff]);
  }
}
