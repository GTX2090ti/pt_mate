import '../../models/app_models.dart';
import '../../utils/format.dart';
import 'base_web_adapter.dart';

class FieldExtractionResult {
  final ExtractedValue first;
  final List<String> allValues;

  const FieldExtractionResult({required this.first, required this.allValues});
}

/// 字段提取配置
/// 与现有 JSON 配置 100% 兼容的 Dart 表示
class FieldConfig {
  final String? selector;
  final String? attribute;
  final Map<String, dynamic>? filter;
  final dynamic defaultValue;
  final bool required;
  final String? value;
  final Map<String, dynamic> json;
  final RegExp? regexpFilter;
  final String? filterFormat;

  FieldConfig({
    this.selector,
    this.attribute,
    this.filter,
    this.defaultValue,
    this.required = false,
    this.value,
  }) : json = {
         'selector': ?selector,
         'attribute': ?attribute,
         'filter': ?filter,
         'value': ?value,
         'defaultValue': ?defaultValue,
         if (required) 'required': required,
       },
       regexpFilter = _compileRegexpFilter(filter),
       filterFormat = filter?['value'] as String?;

  FieldConfig._({
    this.selector,
    this.attribute,
    this.filter,
    this.defaultValue,
    this.required = false,
    this.value,
    required this.json,
    this.regexpFilter,
    this.filterFormat,
  });

  /// 从 JSON/Map 构造，兼容现有配置格式
  factory FieldConfig.fromJson(Map<String, dynamic> json) {
    final filter = json['filter'] as Map<String, dynamic>?;
    return FieldConfig._(
      selector: json['selector'] as String?,
      attribute: json['attribute'] as String?,
      filter: filter,
      defaultValue: json['defaultValue'],
      required: json['required'] as bool? ?? false,
      value: json['value'] as String?,
      json: Map<String, dynamic>.from(json),
      regexpFilter: _compileRegexpFilter(filter),
      filterFormat: filter?['value'] as String?,
    );
  }

  /// 转换为 Map，用于传给 BaseWebAdapterMixin.extractFieldValue
  Map<String, dynamic> toJson() => json;

  bool get hasDefaultValue => defaultValue != null;

  String get defaultValueString => defaultValue.toString();

  /// 是否配置了 value 模板
  bool get hasValue => value != null && value!.isNotEmpty;

  static RegExp? _compileRegexpFilter(Map<String, dynamic>? filter) {
    if (filter == null || filter['name'] != 'regexp') return null;
    final args = filter['args'] as String?;
    if (args == null) return null;
    try {
      return RegExp(args);
    } catch (_) {
      return null;
    }
  }
}

/// 提取结果封装
/// 提供链式类型转换，避免业务层重复的空值检查
class ExtractedValue {
  final String? raw;
  final bool found;

  const ExtractedValue._(this.raw, this.found);

  factory ExtractedValue.missing() => const ExtractedValue._(null, false);

  factory ExtractedValue.fromString(String? value) {
    if (value == null || value.isEmpty) {
      return const ExtractedValue._(null, false);
    }
    return ExtractedValue._(value, true);
  }

  /// 原始字符串值
  String? get string => raw;

  /// 非空字符串，未找到时返回空字符串
  String get stringOrEmpty => raw ?? '';

  /// 解析为整数
  int? get intValue => raw != null ? FormatUtil.parseInt(raw) : null;

  /// 解析为整数，带默认值
  int intValueOr(int defaultValue) => intValue ?? defaultValue;

  /// 解析为 double
  double? get doubleValue =>
      raw != null ? double.tryParse(raw!.replaceAll(',', '')) : null;

  /// 解析日期时间
  DateTime? parseDateTime({String? format, String? zone, String? fieldName}) {
    if (raw == null || raw!.isEmpty) return null;
    try {
      return Formatters.parseDateTimeCustom(
        raw,
        format: format,
        zone: zone,
        fieldName: fieldName,
      );
    } catch (_) {
      return null;
    }
  }

  /// 是否找到有效值
  bool get hasValue => found && raw != null && raw!.isNotEmpty;

  /// 布尔判断：值存在即为 true（用于 collection、isTop 等字段）
  bool get asBool => found;

  @override
  String toString() => 'ExtractedValue(raw: $raw, found: $found)';
}

/// 类型转换工具集合
/// 纯函数，Isolate 安全
class TypedConverter {
  static final RegExp _sizeRegExp = RegExp(r'([\d.]+)\s*(\w+)');

  /// 解析文件大小字符串为字节数
  /// 支持: B, KB/KiB, MB/MiB, GB/GiB, TB/TiB
  static int parseSizeToBytes(String? sizeText) {
    if (sizeText == null || sizeText.isEmpty) return 0;

    final match = _sizeRegExp.firstMatch(sizeText);
    if (match == null) return 0;

    final sizeValue = double.tryParse(match.group(1) ?? '0') ?? 0;
    final unit = match.group(2)?.toUpperCase() ?? 'B';

    switch (unit) {
      case 'KB':
      case 'KIB':
        return (sizeValue * 1024).round();
      case 'MB':
      case 'MIB':
        return (sizeValue * 1024 * 1024).round();
      case 'GB':
      case 'GIB':
        return (sizeValue * 1024 * 1024 * 1024).round();
      case 'TB':
      case 'TIB':
        return (sizeValue * 1024 * 1024 * 1024 * 1024).round();
      default:
        return sizeValue.round();
    }
  }

  /// 解析下载状态文本
  static DownloadStatus parseDownloadStatus(String? text) {
    if (text == null || text.isEmpty) return DownloadStatus.none;

    final percentInt = FormatUtil.parseInt(text);
    if (percentInt == null) return DownloadStatus.none;

    if (percentInt == 100) return DownloadStatus.completed;
    return DownloadStatus.downloading;
  }

  /// 解析优惠类型
  static DiscountType parseDiscount(String? raw, Map<String, String> mapping) {
    if (raw == null || raw.isEmpty) return DiscountType.normal;

    final enumValue = mapping[raw];
    if (enumValue == null) return DiscountType.normal;

    for (final type in DiscountType.values) {
      if (type.value == enumValue) return type;
    }
    return DiscountType.normal;
  }

  /// 解析标签类型
  static TagType? parseTagType(String? raw, Map<String, String> mapping) {
    if (raw == null || raw.isEmpty) return null;

    final enumName = mapping[raw];
    if (enumName == null) return null;

    for (final type in TagType.values) {
      if (type.name.toLowerCase() == enumName.toLowerCase()) return type;
      if (type.content == enumName) return type;
    }
    return null;
  }

  /// 组合解析标签：从名称+描述自动匹配 + 映射标签
  static List<TagType> parseTags(
    String torrentName,
    String description,
    List<String> rawTagList,
    Map<String, String> mapping,
  ) {
    final tags = TagType.matchTags('$torrentName $description');

    for (final tagStr in rawTagList) {
      final mappedTag = parseTagType(tagStr, mapping);
      if (mappedTag != null && !tags.contains(mappedTag)) {
        tags.add(mappedTag);
      }
    }

    return tags;
  }

  /// 确保 URL 为绝对路径
  static String resolveUrl(String? relativeUrl, String baseUrl) {
    if (relativeUrl == null || relativeUrl.isEmpty) return '';
    if (relativeUrl.startsWith('http')) return relativeUrl;

    // [移植适配-OHOS] 协议相对 URL（//host/path）：必须沿用 baseUrl 的 scheme。
    // 早期实现只判断了 http 前缀，遇到 `//cdn.xxx.com/a.jpg` 会走下面的
    // 相对路径分支，拼成 `https://site.com//cdn.xxx.com/a.jpg`，
    // 图片必然加载失败。同一站点上「有的封面能显示、有的不能」多由此而来。
    if (relativeUrl.startsWith('//')) {
      final scheme = Uri.tryParse(baseUrl)?.scheme;
      return '${scheme != null && scheme.isNotEmpty ? scheme : 'https'}:'
          '$relativeUrl';
    }

    final cleanBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final separator = relativeUrl.startsWith('/') ? '' : '/';
    return '$cleanBase$separator$relativeUrl';
  }

  /// 处理下载链接模板替换
  static String resolveDownloadUrl(
    String template,
    String torrentId,
    String passKey,
    String baseUrl, {
    String? userId,
  }) {
    var url = template;
    url = url.replaceAll('{torrentId}', torrentId);
    url = url.replaceAll('{passKey}', passKey);
    if (userId != null) {
      url = url.replaceAll('{userId}', userId);
    }
    final cleanBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    url = url.replaceAll('{baseUrl}', cleanBase);
    return url;
  }
}

/// 声明式 HTML 提取器
/// 基于 BaseWebAdapterMixin 提供的高层封装
class HtmlExtractor with BaseWebAdapterMixin {
  static final RegExp _filterGroupRegExp = RegExp(r'\$(\d+)');
  static final RegExp _whitespaceRegExp = RegExp(r'\s+');

  /// 从单个元素提取字段
  Future<ExtractedValue> extractField(
    dynamic element,
    FieldConfig config,
  ) async {
    return extractFieldSync(element, config);
  }

  /// 从单个元素同步提取字段
  ExtractedValue extractFieldSync(dynamic element, FieldConfig config) {
    return extractFieldResultSync(element, config).first;
  }

  /// 同步提取字段，保留全部匹配值，供 tag/category 等多值字段复用。
  FieldExtractionResult extractFieldResultSync(
    dynamic element,
    FieldConfig config,
  ) {
    final values = extractFieldValuesSync(element, config);
    if (values.isEmpty) {
      if (config.hasDefaultValue) {
        final value = ExtractedValue.fromString(config.defaultValueString);
        return FieldExtractionResult(first: value, allValues: const []);
      }
      return FieldExtractionResult(
        first: ExtractedValue.missing(),
        allValues: const [],
      );
    }
    return FieldExtractionResult(
      first: ExtractedValue.fromString(values.first),
      allValues: values,
    );
  }

  /// 同步提取字段值列表，使用已编译的 FieldConfig 避免热循环 Map 分配。
  List<String> extractFieldValuesSync(dynamic element, FieldConfig config) {
    List<dynamic> targetElements = [element];

    final selector = config.selector;
    if (selector != null && selector.isNotEmpty) {
      targetElements = findElementBySelector(element, selector);
    }

    if (targetElements.isEmpty) {
      return [];
    }

    final values = <String>[];
    for (final targetElement in targetElements) {
      if (targetElement == null) continue;

      String? value;
      if (config.attribute == 'text') {
        value = targetElement.text?.trim();
      } else if (config.attribute == 'href') {
        value = targetElement.attributes['href'];
      } else if (config.attribute != null &&
          config.attribute!.contains('|')) {
        // [移植适配-OHOS] 属性回退：配置形如 `data-src|data-original|src`
        // 时按序取第一个非空值。懒加载封面常把真实地址放在 data-* 上，
        // 未进入视口时该属性为空，导致「部分种子没有封面」。
        for (final candidate in config.attribute!.split('|')) {
          final candidateValue = targetElement.attributes[candidate.trim()];
          if (candidateValue != null && candidateValue.trim().isNotEmpty) {
            value = candidateValue;
            break;
          }
        }
      } else {
        value = targetElement.attributes[config.attribute ?? 'text'];
        // [移植适配-OHOS] 通用回退：懒加载封面把真实地址放在 data-* 上，
        // 未进入视口时该属性为空；而设备上的站点配置是从旧模板固化下来的
        // （attribute 写死 data-src），改内置模板对已有站点无效，
        // 因此必须在代码层兜底尝试其它常见属性。
        if (value == null || value.trim().isEmpty) {
          for (final candidate in const [
            'data-src',
            'data-original',
            'data-url',
            'src',
          ]) {
            if (candidate == config.attribute) continue;
            final fallback = targetElement.attributes[candidate];
            if (fallback != null &&
                fallback.trim().isNotEmpty &&
                !_looksLikePlaceholder(fallback)) {
              value = fallback;
              break;
            }
          }
        }
      }

      if (value != null) {
        value = _applyCompiledFilter(value, config);
      }

      if (value != null && value.isNotEmpty) {
        values.add(
          value.replaceAll('\n', ' ').replaceAll(_whitespaceRegExp, ' '),
        );
      }
    }

    return values;
  }

  /// 判断是否为懒加载占位图（1x1 透明图 / loading 动画 / data URI 等）。
  /// 这类值若当成封面使用，界面上会显示成灰白块，比「不显示封面」更糟，
  /// 因此回退时必须跳过。
  static bool _looksLikePlaceholder(String value) {
    final text = value.toLowerCase().trim();
    if (text.isEmpty) return true;
    if (text.startsWith('data:image')) return true;
    return text.contains('loading') ||
        text.contains('placeholder') ||
        text.contains('blank') ||
        text.contains('spacer') ||
        text.contains('nopicture') ||
        text.contains('noimage') ||
        text.contains('default.gif') ||
        text.contains('default.png') ||
        text.contains('default.jpg');
  }

  String? _applyCompiledFilter(String value, FieldConfig config) {
    final regex = config.regexpFilter;
    if (regex == null) {
      if (config.filter == null) return value;
      return applyFilter(value, config.filter!);
    }
    final match = regex.firstMatch(value);
    if (match == null) return null;

    final template = config.filterFormat ?? r'$0';
    return template.replaceAllMapped(_filterGroupRegExp, (m) {
      final groupIndex = int.parse(m.group(1)!);
      if (groupIndex <= match.groupCount) {
        return match.group(groupIndex) ?? '';
      }
      return m.group(0)!;
    });
  }

  /// 提取整行/整组字段
  /// 返回字段名到提取值的映射
  Future<Map<String, ExtractedValue>> extractRow(
    dynamic rowElement,
    Map<String, FieldConfig> fields,
  ) async {
    return extractRowSync(rowElement, fields);
  }

  /// 同步提取整行/整组字段
  Map<String, ExtractedValue> extractRowSync(
    dynamic rowElement,
    Map<String, FieldConfig> fields,
  ) {
    final result = <String, ExtractedValue>{};

    for (final entry in fields.entries) {
      result[entry.key] = extractFieldSync(rowElement, entry.value);
    }

    return result;
  }

  /// 同步提取整行/整组字段，并保留每个字段的全部匹配值。
  Map<String, FieldExtractionResult> extractRowResultsSync(
    dynamic rowElement,
    Map<String, FieldConfig> fields,
  ) {
    final result = <String, FieldExtractionResult>{};

    for (final entry in fields.entries) {
      result[entry.key] = extractFieldResultSync(rowElement, entry.value);
    }

    return result;
  }

  /// 从 `Map<String, dynamic>` 配置批量构造 FieldConfig
  static Map<String, FieldConfig> parseFieldConfigs(
    Map<String, dynamic>? fieldsConfig,
  ) {
    if (fieldsConfig == null) return {};

    final result = <String, FieldConfig>{};
    for (final entry in fieldsConfig.entries) {
      if (entry.value is Map<String, dynamic>) {
        result[entry.key] = FieldConfig.fromJson(
          entry.value as Map<String, dynamic>,
        );
      }
    }
    return result;
  }

  /// 查找行元素列表
  List<dynamic> findRows(dynamic soup, String rowSelector) {
    return findElementBySelector(soup, rowSelector);
  }

  /// 查找第一个匹配元素
  dynamic findFirst(dynamic soup, String selector) {
    return findFirstElementBySelector(soup, selector);
  }
}
