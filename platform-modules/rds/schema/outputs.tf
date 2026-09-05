output "schema_names" {
  value = [for s in postgresql_schema.this : s.name]
}