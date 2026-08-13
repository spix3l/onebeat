#include "model/json.h"

#include <algorithm>
#include <array>
#include <charconv>
#include <clocale>
#include <cmath>
#include <cstdio>
#include <cstdlib>

namespace onebeat::model::json {
namespace {

// The C library formats and parses decimals with the *locale's* decimal point.
// Nothing in the engine calls setlocale, but the app links Flutter, plugins run
// third-party code, and any of them may. So both directions ask what the
// separator currently is and convert to '.', which is the only separator the
// format has. One call, no cached state, correct even if the locale changes
// between two saves.
char localeDecimalPoint() {
  const lconv* conv = std::localeconv();
  if (conv == nullptr || conv->decimal_point == nullptr || conv->decimal_point[0] == '\0') {
    return '.';
  }
  return conv->decimal_point[0];
}

bool isDigit(char c) {
  return c >= '0' && c <= '9';
}

class Parser {
 public:
  Parser(std::string_view text, ParseError& error) : text_(text), error_(error) {}

  std::optional<Value> run() {
    skipWhitespace();
    std::optional<Value> value = parseValue(0);
    if (!value) return std::nullopt;
    skipWhitespace();
    if (position_ != text_.size()) {
      fail("unexpected trailing content");
      return std::nullopt;
    }
    return value;
  }

 private:
  // Depth is bounded so a hostile or corrupt file cannot recurse the parser
  // into a stack overflow. Real projects nest about six deep.
  static constexpr int MaxDepth = 64;

  std::optional<Value> parseValue(int depth) {
    if (depth > MaxDepth) {
      fail("nesting too deep");
      return std::nullopt;
    }
    if (atEnd()) {
      fail("unexpected end of input");
      return std::nullopt;
    }
    switch (peek()) {
      case '{':
        return parseObject(depth);
      case '[':
        return parseArray(depth);
      case '"': {
        std::string text;
        if (!parseString(text)) return std::nullopt;
        return Value::string(std::move(text));
      }
      case 't':
        return parseLiteral("true", Value::boolean(true));
      case 'f':
        return parseLiteral("false", Value::boolean(false));
      case 'n':
        return parseLiteral("null", Value::null());
      default:
        return parseNumber();
    }
  }

  std::optional<Value> parseLiteral(std::string_view word, Value value) {
    if (text_.substr(position_, word.size()) != word) {
      fail("unrecognised token");
      return std::nullopt;
    }
    advance(word.size());
    return value;
  }

  std::optional<Value> parseObject(int depth) {
    advance(1);  // '{'
    Object object;
    skipWhitespace();
    if (!atEnd() && peek() == '}') {
      advance(1);
      return Value::object(std::move(object));
    }
    while (true) {
      skipWhitespace();
      if (atEnd() || peek() != '"') {
        fail("expected a key");
        return std::nullopt;
      }
      std::string key;
      if (!parseString(key)) return std::nullopt;
      skipWhitespace();
      if (atEnd() || peek() != ':') {
        fail("expected ':' after key");
        return std::nullopt;
      }
      advance(1);
      skipWhitespace();
      std::optional<Value> value = parseValue(depth + 1);
      if (!value) return std::nullopt;
      // A duplicate key is not an error in JSON and every parser resolves it
      // differently. Last one wins, which is what a hand-edit appended to the
      // end of an object means.
      object.insert_or_assign(std::move(key), std::move(*value));
      skipWhitespace();
      if (atEnd()) {
        fail("unterminated object");
        return std::nullopt;
      }
      if (peek() == ',') {
        advance(1);
        continue;
      }
      if (peek() == '}') {
        advance(1);
        return Value::object(std::move(object));
      }
      fail("expected ',' or '}'");
      return std::nullopt;
    }
  }

  std::optional<Value> parseArray(int depth) {
    advance(1);  // '['
    Array array;
    skipWhitespace();
    if (!atEnd() && peek() == ']') {
      advance(1);
      return Value::array(std::move(array));
    }
    while (true) {
      skipWhitespace();
      std::optional<Value> value = parseValue(depth + 1);
      if (!value) return std::nullopt;
      array.push_back(std::move(*value));
      skipWhitespace();
      if (atEnd()) {
        fail("unterminated array");
        return std::nullopt;
      }
      if (peek() == ',') {
        advance(1);
        continue;
      }
      if (peek() == ']') {
        advance(1);
        return Value::array(std::move(array));
      }
      fail("expected ',' or ']'");
      return std::nullopt;
    }
  }

  bool parseString(std::string& out) {
    advance(1);  // '"'
    out.clear();
    while (true) {
      if (atEnd()) {
        fail("unterminated string");
        return false;
      }
      const char c = peek();
      if (c == '"') {
        advance(1);
        return true;
      }
      if (c == '\\') {
        advance(1);
        if (atEnd()) {
          fail("unterminated escape");
          return false;
        }
        const char escape = peek();
        advance(1);
        switch (escape) {
          case '"':
            out.push_back('"');
            break;
          case '\\':
            out.push_back('\\');
            break;
          case '/':
            out.push_back('/');
            break;
          case 'b':
            out.push_back('\b');
            break;
          case 'f':
            out.push_back('\f');
            break;
          case 'n':
            out.push_back('\n');
            break;
          case 'r':
            out.push_back('\r');
            break;
          case 't':
            out.push_back('\t');
            break;
          case 'u': {
            uint32_t code = 0;
            if (!parseHex4(code)) return false;
            // Surrogate pair: the escape form is UTF-16, the file is UTF-8.
            if (code >= 0xD800 && code <= 0xDBFF && text_.substr(position_, 2) == "\\u") {
              const size_t mark = position_;
              advance(2);
              uint32_t low = 0;
              if (!parseHex4(low)) return false;
              if (low >= 0xDC00 && low <= 0xDFFF) {
                code = 0x10000 + ((code - 0xD800) << 10U) + (low - 0xDC00);
              } else {
                position_ = mark;  // not a pair; leave the lone high surrogate
              }
            }
            appendUtf8(code, out);
            break;
          }
          default:
            fail("unrecognised escape");
            return false;
        }
        continue;
      }
      if (static_cast<unsigned char>(c) < 0x20) {
        fail("control character in string");
        return false;
      }
      out.push_back(c);
      advance(1);
    }
  }

  bool parseHex4(uint32_t& out) {
    if (position_ + 4 > text_.size()) {
      fail("truncated \\u escape");
      return false;
    }
    out = 0;
    for (int i = 0; i < 4; ++i) {
      const char c = text_[position_ + static_cast<size_t>(i)];
      uint32_t digit = 0;
      if (isDigit(c)) {
        digit = static_cast<uint32_t>(c - '0');
      } else if (c >= 'a' && c <= 'f') {
        digit = static_cast<uint32_t>(c - 'a') + 10;
      } else if (c >= 'A' && c <= 'F') {
        digit = static_cast<uint32_t>(c - 'A') + 10;
      } else {
        fail("bad hex digit in \\u escape");
        return false;
      }
      out = (out << 4U) | digit;
    }
    advance(4);
    return true;
  }

  static void appendUtf8(uint32_t code, std::string& out) {
    const auto byte = [&out](uint32_t value) { out.push_back(static_cast<char>(value)); };
    if (code < 0x80) {
      byte(code);
    } else if (code < 0x800) {
      byte(0xC0 | (code >> 6U));
      byte(0x80 | (code & 0x3FU));
    } else if (code < 0x10000) {
      byte(0xE0 | (code >> 12U));
      byte(0x80 | ((code >> 6U) & 0x3FU));
      byte(0x80 | (code & 0x3FU));
    } else {
      byte(0xF0 | (code >> 18U));
      byte(0x80 | ((code >> 12U) & 0x3FU));
      byte(0x80 | ((code >> 6U) & 0x3FU));
      byte(0x80 | (code & 0x3FU));
    }
  }

  std::optional<Value> parseNumber() {
    const size_t start = position_;
    if (!atEnd() && peek() == '-') advance(1);
    while (!atEnd() && isDigit(peek())) advance(1);

    // How the number was *written* decides its type. `960` is ticks; `960.0`
    // is a real that happens to be whole, and writing it back as `960` would
    // change the file (see json.h).
    bool integral = true;
    if (!atEnd() && peek() == '.') {
      integral = false;
      advance(1);
      while (!atEnd() && isDigit(peek())) advance(1);
    }
    if (!atEnd() && (peek() == 'e' || peek() == 'E')) {
      integral = false;
      advance(1);
      if (!atEnd() && (peek() == '+' || peek() == '-')) advance(1);
      while (!atEnd() && isDigit(peek())) advance(1);
    }

    const std::string_view token = text_.substr(start, position_ - start);
    if (token.empty() || token == "-") {
      fail("expected a value");
      return std::nullopt;
    }

    if (integral) {
      int64_t number = 0;
      const auto* first = token.data();
      const auto result = std::from_chars(first, first + token.size(), number);
      if (result.ec == std::errc{} && result.ptr == first + token.size()) {
        return Value::integer(number);
      }
      // Out of int64 range: keep it as a real rather than refusing the file.
      // Nothing the model reads as an integer can legitimately be that large,
      // so the field-level check downstream reports it with a useful name.
    }

    std::string text(token);
    const char point = localeDecimalPoint();
    if (point != '.') std::replace(text.begin(), text.end(), '.', point);
    char* parse_end = nullptr;
    const double number = std::strtod(text.c_str(), &parse_end);
    if (parse_end != text.c_str() + text.size()) {
      fail("malformed number");
      return std::nullopt;
    }
    return Value::real(number);
  }

  void skipWhitespace() {
    while (!atEnd()) {
      const char c = peek();
      if (c != ' ' && c != '\t' && c != '\n' && c != '\r') break;
      advance(1);
    }
  }

  bool atEnd() const { return position_ >= text_.size(); }
  char peek() const { return text_[position_]; }

  void advance(size_t count) {
    for (size_t i = 0; i < count && position_ < text_.size(); ++i) {
      if (text_[position_] == '\n') {
        ++line_;
        column_ = 1;
      } else {
        ++column_;
      }
      ++position_;
    }
  }

  void fail(std::string message) {
    if (!error_.message.empty()) return;  // keep the first, innermost failure
    error_.line = line_;
    error_.column = column_;
    error_.message = std::move(message);
  }

  std::string_view text_;
  ParseError& error_;
  size_t position_ = 0;
  int line_ = 1;
  int column_ = 1;
};

// ---------------------------------------------------------------------------
// Writer
// ---------------------------------------------------------------------------

// The shape that must stay on one line: all numbers, optionally with a single
// trailing object. That is exactly a note record — four integers plus the
// per-note properties of docs/project-format.md §5.2 — and keeping it on one
// line is the whole of the format's claim to be diffable: three notes added is
// three lines added, whether or not they carry properties.
bool isOneLineArray(const Array& array) {
  // The trailing object qualifies only when numbers came first, so an array
  // *of* objects never collapses — one such element would be inline and two
  // would not, and a diff that changes shape when a second entry appears is
  // exactly what this format is trying not to do.
  if (array.empty() || !array.front().isNumber()) return false;
  for (size_t i = 0; i < array.size(); ++i) {
    if (array[i].isNumber()) continue;
    if (array[i].isObject() && i + 1 == array.size()) continue;
    return false;
  }
  return true;
}

class Writer {
 public:
  bool write(const Value& value, const std::vector<std::string>& root_order) {
    writeValue(value, 0, &root_order);
    return ok_;
  }

  std::string take() { return std::move(out_); }

 private:
  void indent(int depth) { out_.append(static_cast<size_t>(depth) * 2, ' '); }

  void writeValue(const Value& value, int depth, const std::vector<std::string>* root_order) {
    switch (value.type()) {
      case Value::Type::Null:
        out_ += "null";
        return;
      case Value::Type::Bool:
        out_ += value.asBool() ? "true" : "false";
        return;
      case Value::Type::Int:
        out_ += std::to_string(value.asInt());
        return;
      case Value::Type::Real: {
        const double number = value.asDouble();
        if (!std::isfinite(number)) {
          ok_ = false;  // §6.6: NaN and ±inf are rejected, never written as null
          out_ += "null";
          return;
        }
        out_ += formatReal(number);
        return;
      }
      case Value::Type::String:
        out_ += escapeString(*value.asString());
        return;
      case Value::Type::Array:
        writeArray(*value.asArray(), depth);
        return;
      case Value::Type::Object:
        writeObject(*value.asObject(), depth, root_order);
        return;
    }
  }

  // Everything on one line, keys still sorted. Only reachable from a one-line
  // array, so the "one element per line" rule still governs everywhere else.
  void writeInline(const Value& value) {
    if (const Object* object = value.asObject(); object != nullptr) {
      out_ += "{";
      bool first = true;
      for (const auto& [key, child] : *object) {
        if (!first) out_ += ", ";
        first = false;
        out_ += escapeString(key);
        out_ += ": ";
        writeInline(child);
      }
      out_ += "}";
      return;
    }
    if (const Array* array = value.asArray(); array != nullptr) {
      out_ += "[";
      for (size_t i = 0; i < array->size(); ++i) {
        if (i > 0) out_ += ", ";
        writeInline((*array)[i]);
      }
      out_ += "]";
      return;
    }
    writeValue(value, 0, nullptr);
  }

  void writeArray(const Array& array, int depth) {
    if (array.empty()) {
      out_ += "[]";
      return;
    }
    if (isOneLineArray(array)) {
      out_ += "[";
      for (size_t i = 0; i < array.size(); ++i) {
        if (i > 0) out_ += ", ";
        writeInline(array[i]);
      }
      out_ += "]";
      return;
    }
    out_ += "[\n";
    for (size_t i = 0; i < array.size(); ++i) {
      indent(depth + 1);
      writeValue(array[i], depth + 1, nullptr);
      out_ += i + 1 < array.size() ? ",\n" : "\n";
    }
    indent(depth);
    out_ += "]";
  }

  void writeObject(const Object& object, int depth, const std::vector<std::string>* root_order) {
    if (object.empty()) {
      out_ += "{}";
      return;
    }
    std::vector<const Object::value_type*> entries;
    entries.reserve(object.size());
    if (root_order != nullptr) {
      for (const std::string& key : *root_order) {
        const auto entry = object.find(key);
        if (entry != object.end()) entries.push_back(&*entry);
      }
    }
    for (const auto& entry : object) {
      const bool hoisted =
          root_order != nullptr &&
          std::find(root_order->begin(), root_order->end(), entry.first) != root_order->end();
      if (!hoisted) entries.push_back(&entry);
    }

    out_ += "{\n";
    for (size_t i = 0; i < entries.size(); ++i) {
      indent(depth + 1);
      out_ += escapeString(entries[i]->first);
      out_ += ": ";
      writeValue(entries[i]->second, depth + 1, nullptr);
      out_ += i + 1 < entries.size() ? ",\n" : "\n";
    }
    indent(depth);
    out_ += "}";
  }

  std::string out_;
  bool ok_ = true;
};

}  // namespace

// ---------------------------------------------------------------------------
// Value
// ---------------------------------------------------------------------------

Value Value::boolean(bool value) {
  Value result;
  result.type_ = Type::Bool;
  result.bool_ = value;
  return result;
}

Value Value::integer(int64_t value) {
  Value result;
  result.type_ = Type::Int;
  result.int_ = value;
  return result;
}

Value Value::real(double value) {
  Value result;
  result.type_ = Type::Real;
  result.real_ = value;
  return result;
}

Value Value::string(std::string value) {
  Value result;
  result.type_ = Type::String;
  result.string_ = std::move(value);
  return result;
}

Value Value::array(Array value) {
  Value result;
  result.type_ = Type::Array;
  result.array_ = std::make_shared<Array>(std::move(value));
  return result;
}

Value Value::object(Object value) {
  Value result;
  result.type_ = Type::Object;
  result.object_ = std::make_shared<Object>(std::move(value));
  return result;
}

int64_t Value::asInt(int64_t fallback) const {
  if (isInt()) return int_;
  // A real is accepted only when it is exactly an integer: a hand-edited
  // `"start": 480.0` is unambiguous, `480.5` is a tick position that does not
  // exist and silently truncating it would move a note.
  if (isReal() && std::isfinite(real_) && real_ == std::trunc(real_) && real_ >= -9.2e18 &&
      real_ <= 9.2e18) {
    return static_cast<int64_t>(real_);
  }
  return fallback;
}

double Value::asDouble(double fallback) const {
  if (isReal()) return real_;
  if (isInt()) return static_cast<double>(int_);
  return fallback;
}

const std::string* Value::asString() const {
  return isString() ? &string_ : nullptr;
}
const Array* Value::asArray() const {
  return isArray() ? array_.get() : nullptr;
}
const Object* Value::asObject() const {
  return isObject() ? object_.get() : nullptr;
}
Object* Value::asObject() {
  return isObject() ? object_.get() : nullptr;
}

const Value* Value::find(std::string_view key) const {
  const Object* object = asObject();
  if (object == nullptr) return nullptr;
  const auto entry = object->find(std::string(key));
  return entry == object->end() ? nullptr : &entry->second;
}

std::string ParseError::describe() const {
  return "line " + std::to_string(line) + ", column " + std::to_string(column) + ": " + message;
}

std::optional<Value> parse(std::string_view text, ParseError& error) {
  error = ParseError{};
  // A UTF-8 BOM is not JSON, but editors add one and refusing the file over it
  // would be pedantry. We never write one (§6.1).
  if (text.size() >= 3 && text.substr(0, 3) == "\xEF\xBB\xBF") text.remove_prefix(3);
  Parser parser(text, error);
  std::optional<Value> value = parser.run();
  if (!value && error.message.empty()) error.message = "malformed JSON";
  return value;
}

std::string formatReal(double value) {
  std::array<char, 64> buffer{};
  const int written = std::snprintf(buffer.data(), buffer.size(), "%.6f", value);
  if (written <= 0) return "0.000000";
  std::string text(buffer.data(), static_cast<size_t>(written));

  const char point = localeDecimalPoint();
  if (point != '.') std::replace(text.begin(), text.end(), point, '.');

  // §6.6: `-0` is written `0.000000`. A pan of exactly zero must not depend on
  // which side the user dragged from.
  if (text == "-0.000000") return "0.000000";
  return text;
}

std::string escapeString(std::string_view text) {
  std::string out;
  out.reserve(text.size() + 2);
  out.push_back('"');
  for (const char c : text) {
    // §6.7: only what JSON requires. Non-ASCII goes through literally, so a
    // pattern named "サビ" stays readable in a diff.
    switch (c) {
      case '"':
        out += "\\\"";
        break;
      case '\\':
        out += "\\\\";
        break;
      default:
        if (static_cast<unsigned char>(c) < 0x20) {
          std::array<char, 8> escape{};
          std::snprintf(escape.data(), escape.size(), "\\u%04x", static_cast<unsigned char>(c));
          out += escape.data();
        } else {
          out.push_back(c);
        }
    }
  }
  out.push_back('"');
  return out;
}

std::optional<std::string> writeCanonical(const Value& root,
                                          const std::vector<std::string>& root_key_order) {
  Writer writer;
  if (!writer.write(root, root_key_order)) return std::nullopt;
  std::string text = writer.take();
  text.push_back('\n');  // §6.1: exactly one trailing newline
  return text;
}

}  // namespace onebeat::model::json
