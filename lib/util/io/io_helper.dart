//todo 这里要实装系统代理和自定义代理
class IOHelper {
  static final _instance = IOHelper._();

  IOHelper._();

  factory IOHelper() => _instance;
}
