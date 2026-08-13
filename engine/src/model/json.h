// A JSON value, a parser, and the canonical writer of docs/project-format.md §6
// (OB-3-05 §1).
//
// Why not a library: the writer here is not "JSON output", it is *one specific
// byte sequence per model* — key order, six-decimal floats, numeric arrays on
// one line, notes one per line. No general library emits that without being
// fought, and the fight is larger than the parser. The parser is the small half.
//
// Two properties this file owes the rest of the format:
//
//   1. **Integers stay integers.** Ticks are int64 and must round-trip exactly;
//      a value that stores every number as a double loses ticks above 2^53 and,
//      worse, writes `960.0` where the format says `960`. `Int` and `Real` are
//      therefore distinct types, and the parser decides between them by *how the
//      number was written*.
//   2. **Locale cannot reach the file.** `snprintf`/`strtod` respect the C
//      locale's decimal point, so a French user would write `0,500000` and every
//      round-trip test would pass on their machine and nowhere else. Both
//      directions go through `localeconv()` and normalise (see json.cpp).
//
// Objects are `std::map`, so "sorted by key" is not something the writer has to
// remember to do.
#pragma once

#include <cstdint>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace onebeat::model::json {

class Value;

using Object = std::map<std::string, Value>;
using Array = std::vector<Value>;

class Value {
 public:
  enum class Type : uint8_t { Null, Bool, Int, Real, String, Array, Object };

  Value() = default;

  // Named constructors rather than overloads: `Value("x")` picking the bool
  // overload is a classic, and a project file with `true` where a name belongs
  // is not a bug anyone enjoys finding.
  static Value null() { return Value{}; }
  static Value boolean(bool value);
  static Value integer(int64_t value);
  static Value real(double value);
  static Value real(float value) { return real(static_cast<double>(value)); }
  static Value string(std::string value);
  static Value array(Array value);
  static Value object(Object value);

  Type type() const { return type_; }
  bool isNull() const { return type_ == Type::Null; }
  bool isBool() const { return type_ == Type::Bool; }
  bool isInt() const { return type_ == Type::Int; }
  bool isReal() const { return type_ == Type::Real; }
  bool isNumber() const { return isInt() || isReal(); }
  bool isString() const { return type_ == Type::String; }
  bool isArray() const { return type_ == Type::Array; }
  bool isObject() const { return type_ == Type::Object; }

  // Accessors return null on type mismatch rather than throwing: every caller
  // in the loader is asking "is this field the shape I expect?", and a file
  // that answers no is a load report entry, not an exception.
  bool asBool(bool fallback = false) const { return isBool() ? bool_ : fallback; }
  int64_t asInt(int64_t fallback = 0) const;
  double asDouble(double fallback = 0.0) const;
  const std::string* asString() const;
  const Array* asArray() const;
  const Object* asObject() const;
  Object* asObject();

  // Object field lookup. Returns nullptr when absent — the loader's usual path.
  const Value* find(std::string_view key) const;

 private:
  Type type_ = Type::Null;
  bool bool_ = false;
  int64_t int_ = 0;
  double real_ = 0.0;
  std::string string_;
  // Indirection so `Value` is not infinitely sized; `shared_ptr` so copying a
  // residue tree around the loader is cheap and const-correct (nothing mutates
  // a value after it is parsed except through `asObject()` on the residue).
  std::shared_ptr<Array> array_;
  std::shared_ptr<Object> object_;
};

struct ParseError {
  int line = 0;    // 1-based, as an editor shows it
  int column = 0;  // 1-based, in bytes
  std::string message;

  std::string describe() const;
};

// Parses UTF-8 JSON. On failure returns nullopt and fills `error` with a
// position, because "malformed JSON" without a line number is not a report a
// person can act on (docs/project-format.md §8).
std::optional<Value> parse(std::string_view text, ParseError& error);

// The canonical form of docs/project-format.md §6, ending in exactly one
// newline. `root_key_order` names keys hoisted to the front of the top-level
// object in the order given; every other key sorts ascending.
//
// Returns nullopt if the tree contains a non-finite number: NaN has no JSON
// spelling, and writing `null` for it would silently turn a broken value into a
// missing one (§6.6).
std::optional<std::string> writeCanonical(const Value& root,
                                          const std::vector<std::string>& root_key_order = {});

// Exposed for the writer's tests and for anything else that must produce the
// format's number spellings: bare integers, and exactly six decimals otherwise,
// never in exponent notation, never locale-dependent.
std::string formatReal(double value);
std::string escapeString(std::string_view text);

}  // namespace onebeat::model::json
