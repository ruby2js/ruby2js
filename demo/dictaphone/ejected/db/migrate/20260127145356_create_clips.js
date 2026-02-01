export const migration = {
  up: async adapter => (
    await adapter.createTable("clips", [
      {name: "id", type: "integer", primaryKey: true, autoIncrement: true},
      {name: "name", type: "string"},
      {name: "transcript", type: "text"},
      {name: "duration", type: "float"},
      {name: "created_at", type: "datetime", null: false},
      {name: "updated_at", type: "datetime", null: false}
    ])
  ),

  tableSchemas: {clips: "++id, name, transcript, duration, created_at, updated_at"}
}