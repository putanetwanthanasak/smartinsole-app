// Migration test scaffold for schema v1 (S6A). The schema dump is
// drift_schemas/app_database/drift_schema_v1.json; generated/ comes from
//   dart run drift_dev schema generate drift_schemas/app_database/ \
//       test/drift/app_database/generated/
// When v2 lands: bump `schemaVersion`, run
//   dart run drift_dev make-migrations
// (it dumps v2, writes the step-by-step migration and adds v1 → v2 tests
// next to these), and keep both tests below.
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/storage/database.dart';

import 'generated/schema.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('a database the app creates matches the committed v1 dump', () async {
    // Catches a table change without a schema version bump and a new dump.
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 1);
  });

  test('the app opens an existing v1 database unchanged', () async {
    final db = AppDatabase(await verifier.startAt(1));
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 1);
  });
}
