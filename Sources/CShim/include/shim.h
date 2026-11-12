/// Calls a Swift protocol-extension static method `static func f()` on `Self`,
/// given Self's type metadata and its protocol witness table.
void la_call_static_on_type(void *fn, const void *metadata, const void *witnessTable);
