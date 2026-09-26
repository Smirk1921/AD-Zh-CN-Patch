"use strict";

(() => {
  const catalogue = globalThis.__AD_ZH_CN_CATALOG__;
  if (!catalogue || catalogue.locale !== "zh-CN") {
    console.error("[AD Zh-CN] Translation catalogue is missing or invalid.");
    return;
  }

  const PLACEHOLDER = /\{\{#(\d+)\}\}/gu;
  const HAS_LATIN = /[A-Za-z]/u;
  const HAS_HAN = /[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]/u;
  const TRANSLATABLE_ATTRIBUTES = ["title", "placeholder", "aria-label", "alt", "data-tooltip", "ach-tooltip"];
  const excludedSelector = catalogue.exclusions.join(",");
  const untranslatedSamples = new Set();
  const counters = {
    exact: 0,
    pattern: 0,
    fragment: 0,
    html: 0,
    textNodes: 0,
    attributes: 0
  };

  function canonical(value) {
    return value.replace(/\s+/gu, " ").trim();
  }

  function canonicalForMatching(value) {
    const normalized = canonical(value);
    if (!/<[^>]+>/u.test(normalized)) return normalized;
    // Chromium serializes quoted HTML attributes with double quotes even when
    // the trusted source template used single quotes. Treat those equivalent
    // forms as the same structured fragment without relaxing ordinary text.
    return normalized.replace(/(\s[\w:-]+)='([^']*)'/gu, '$1="$2"');
  }

  // Vue occasionally capitalizes a configured sentence when it renders the
  // text. English source matching is therefore case-insensitive, while
  // collisions which differ only by case are still rejected below.
  function canonicalSource(value) {
    return canonicalForMatching(value).toLocaleLowerCase("en-US");
  }

  function escapeRegularExpression(value) {
    return value.replace(/[.*+?^${}()|[\]\\]/gu, "\\$&");
  }

  function splitTemplate(template) {
    const captures = [];
    const segments = [];
    let cursor = 0;
    for (const match of template.matchAll(PLACEHOLDER)) {
      segments.push(template.slice(cursor, match.index));
      captures.push(Number(match[1]));
      cursor = match.index + match[0].length;
    }
    segments.push(template.slice(cursor));
    return { captures, segments };
  }

  function compileTemplateRule(rule, priority) {
    const template = canonicalForMatching(rule.from);
    const { captures, segments } = splitTemplate(template);
    const replacementCaptures = splitTemplate(rule.to).captures;
    const staticWords = template
      .replace(PLACEHOLDER, " ")
      .match(/[A-Za-z][A-Za-z0-9'-]*/gu) ?? [];
    const anchor = staticWords.sort((left, right) => right.length - left.length)[0]?.toLocaleLowerCase("en-US") ?? "";
    return {
      segments,
      comparableSegments: segments.map(segment => segment.toLocaleLowerCase("en-US")),
      structuredComparableSegments: segments.map(segment => segment.trim().toLocaleLowerCase("en-US")),
      caseInsensitive: true,
      replacement: rule.to,
      captures,
      captureTypes: rule.captureTypes ?? [],
      captureTransforms: rule.captureTransforms ?? [],
      anchor,
      bucketKey: anchor.length >= 3 ? anchor.slice(0, 3) : "",
      newsOnly: rule.scope === "news",
      structured: /<[^>]+>/u.test(template),
      captureOrderPreserved: captures.length === replacementCaptures.length &&
        captures.every((capture, index) => capture === replacementCaptures[index]),
      priority
    };
  }

  function compileTargetRule(rule) {
    const template = canonicalForMatching(rule.to);
    const { captures, segments } = splitTemplate(template);
    const anchor = [...segments].sort((left, right) => right.length - left.length)[0]
      ?.toLocaleLowerCase("zh-CN") ?? "";
    return {
      captures,
      segments,
      comparableSegments: segments,
      caseInsensitive: false,
      bucketKey: anchor.length >= 3 ? anchor.slice(0, 3) : ""
    };
  }

  const newsOnlyCanonical = new Set((catalogue.newsOnlyExact ?? []).map(canonicalSource));
  const canonicalExact = new Map();
  const canonicalConflicts = new Set();
  for (const [source, target] of Object.entries(catalogue.exact)) {
    const key = canonicalSource(source);
    if (!key) continue;
    if (canonicalExact.has(key) && canonicalExact.get(key) !== target) {
      canonicalConflicts.add(key);
    } else {
      canonicalExact.set(key, target);
    }
  }
  for (const key of canonicalConflicts) canonicalExact.delete(key);

  const patternRules = catalogue.patterns.map(compileTemplateRule);
  const patternBuckets = new Map();
  const unbucketedPatterns = [];
  for (const rule of patternRules) {
    if (!rule.bucketKey) {
      unbucketedPatterns.push(rule);
      continue;
    }
    if (!patternBuckets.has(rule.bucketKey)) patternBuckets.set(rule.bucketKey, []);
    patternBuckets.get(rule.bucketKey).push(rule);
  }
  const canonicalTargets = new Set(Object.values(catalogue.exact).map(canonicalForMatching));
  const targetPatternBuckets = new Map();
  const unbucketedTargetPatterns = [];
  for (const rule of catalogue.patterns.map(compileTargetRule)) {
    if (!rule.bucketKey) {
      unbucketedTargetPatterns.push(rule);
      continue;
    }
    if (!targetPatternBuckets.has(rule.bucketKey)) targetPatternBuckets.set(rule.bucketKey, []);
    targetPatternBuckets.get(rule.bucketKey).push(rule);
  }
  const fragmentRules = catalogue.fragments
    .filter(rule => rule.from && rule.to)
    .sort((left, right) => right.from.length - left.from.length)
    .map(rule => ({
      expression: new RegExp(escapeRegularExpression(rule.from), "giu"),
      replacement: rule.to
    }));
  const translatedStructuredHtml = new WeakMap();

  const DURATION_UNITS = new Map([
    ["ms", "毫秒"],
    ["millisecond", "毫秒"],
    ["milliseconds", "毫秒"],
    ["second", "秒"],
    ["seconds", "秒"],
    ["minute", "分钟"],
    ["minutes", "分钟"],
    ["hour", "小时"],
    ["hours", "小时"],
    ["day", "天"],
    ["days", "天"],
    ["year", "年"],
    ["years", "年"]
  ]);

  const ENGLISH_MONTHS = new Map([
    ["Jan", 1], ["Feb", 2], ["Mar", 3], ["Apr", 4],
    ["May", 5], ["Jun", 6], ["Jul", 7], ["Aug", 8],
    ["Sep", 9], ["Oct", 10], ["Nov", 11], ["Dec", 12]
  ]);

  const TERM_LIST = new Map([
    ["Dimensions", "维度"],
    ["Dimension Boosts", "维度提升"],
    ["Dimensions and Dimension Boosts", "维度与维度提升"],
    ["Antimatter", "反物质维度"],
    ["Antimatter and Infinity", "反物质维度和无限维度"],
    ["Antimatter, Infinity, and Time", "反物质维度、无限维度和时间维度"]
  ]);

  const MATTER_VERBS = new Map([
    ["make", "构成"],
    ["fill", "填满"]
  ]);

  // Classifiers are stored with the nouns because Chinese does not have one
  // universal equivalent of the English plural forms used by MatterScale.
  const MATTER_OBJECTS = new Map([
    ["attometers cubed", "立方阿米"],
    ["zeptometers cubed", "立方仄米"],
    ["yoctometers cubed", "立方幺米"],
    ["planck volumes", "普朗克体积"],
    ["protons", "个质子"],
    ["nuclei", "个原子核"],
    ["Hydrogen atoms", "个氢原子"],
    ["viruses", "个病毒"],
    ["red blood cells", "个红细胞"],
    ["grains of sand", "粒沙"],
    ["grains of rice", "粒米"],
    ["teaspoons", "茶匙"],
    ["wine bottles", "瓶酒"],
    ["fridge-freezers", "台冰箱"],
    ["Olympic-sized swimming pools", "座奥林匹克标准泳池"],
    ["Great Pyramids of Giza", "座吉萨大金字塔"],
    ["Great Walls of China", "座万里长城"],
    ["large asteroids", "颗大型小行星"],
    ["dwarf planets", "颗矮行星"],
    ["Earths", "个地球"],
    ["Jupiters", "个木星"],
    ["Suns", "个太阳"],
    ["red giants", "颗红巨星"],
    ["hypergiant stars", "颗特超巨星"],
    ["nebulas", "片星云"],
    ["Oort clouds", "片奥尔特云"],
    ["Local Bubbles", "个本地泡"],
    ["galaxies", "个星系"],
    ["Local Groups", "个本星系群"],
    ["Sculptor Voids", "个玉夫座空洞"],
    ["observable universes", "个可观测宇宙"],
    ["Dimensions", "个维度"],
    ["Infinity Dimensions", "个无限维度"],
    ["Time Dimensions", "个时间维度"]
  ]);

  const THEMES = new Map([
    ["Normal", "普通"],
    ["Metro", "Metro 风格"],
    ["Dark", "深色"],
    ["Dark Metro", "深色 Metro"],
    ["Inverted", "反色"],
    ["Inverted Metro", "反色 Metro"],
    ["AMOLED", "AMOLED"],
    ["AMOLED Metro", "AMOLED Metro"],
    ["Christmas", "圣诞"]
  ]);

  const NOTATIONS = new Map([
    ["Scientific", "科学记数法"],
    ["Engineering", "工程记数法"],
    ["Letters", "字母记数法"],
    ["Standard", "标准记数法"],
    ["Emoji", "表情符号记数法"],
    ["Mixed scientific", "混合科学记数法"],
    ["Mixed engineering", "混合工程记数法"],
    ["Logarithm", "对数记数法"],
    ["Brackets", "括号记数法"],
    ["Infinity", "无限记数法"],
    ["Roman", "罗马数字记数法"],
    ["Dots", "点阵记数法"],
    ["Zalgo", "Zalgo 记数法"],
    ["Hex", "十六进制记数法"],
    ["Imperial", "英制单位记数法"],
    ["Clock", "时钟记数法"],
    ["Prime", "质数记数法"],
    ["Bar", "条形记数法"],
    ["Shi", "中文数字记数法"],
    ["Blind", "盲文记数法"],
    ["Blobs", "色块记数法"],
    ["ALL", "全部记数法"]
  ]);

  const SIDEBAR_RESOURCES = new Map([
    ["Latest Resource", "最新资源"],
    ["Blob", "主题色块"],
    ["Antimatter", "反物质"],
    ["Infinity Points", "无限点数"],
    ["Eternity Points", "永恒点数"],
    ["Total TT", "时间之理总量"],
    ["Reality Machines", "现实机器"],
    ["Imaginary Machines", "虚幻机器"],
    ["Dilated Time", "膨胀时间"],
    ["Tachyon Particles", "超光速粒子"],
    ["Replicanti", "复制器"],
    ["Relic Shards", "遗迹碎片"],
    ["All Machines", "全部机器"],
    ["Machines", "机器"],
    ["Dark Matter", "暗物质"],
    ["Dark Energy", "暗能量"],
    ["Singularities", "奇点"],
    ["Reality Shards", "现实碎片"],
    ["Remnants", "残余物"]
  ]);

  function localizeDuration(value) {
    const input = canonical(value);
    // HH:MM:SS and MM:SS already use a locale-neutral compact form.
    if (/^(?:[0-9]{1,3}:)?[0-9]{1,2}:[0-9]{2}(?:\.[0-9])?$/u.test(input)) return input;

    // The value itself may use any of the game's novelty notations (for
    // example ∞, emoji, or a standard-notation suffix). The transform is only
    // invoked for captures already proven to be TimeSpan output, so accepting
    // one non-whitespace value token here remains scoped and deterministic.
    const component = /((?:[<>]\s*)?[^\s]+(?:\s+[A-Za-z]+(?:-[A-Za-z]+)*)?)\s+(milliseconds?|ms|seconds?|minutes?|hours?|days?|years?)/giu;
    const localized = [];
    let cursor = 0;
    let match;
    while ((match = component.exec(input)) !== null) {
      const separator = input.slice(cursor, match.index);
      if ((localized.length === 0 && separator) ||
          (localized.length > 0 && !/^(?:,\s*|\s+and\s+)$/u.test(separator))) return value;
      const unit = DURATION_UNITS.get(match[2].toLocaleLowerCase("en-US"));
      if (!unit) return value;
      localized.push(`${canonical(match[1])} ${unit}`);
      cursor = component.lastIndex;
    }
    if (localized.length === 0 || cursor !== input.length) return value;
    return localized.join(" ");
  }

  function localizeDateTime(value) {
    const match = /^([A-Z][a-z]{2}) ([0-9]{1,2}) ([0-9]{4}) ([0-9]{2}:[0-9]{2}:[0-9]{2})$/u.exec(canonical(value));
    if (!match || !ENGLISH_MONTHS.has(match[1])) return value;
    return `${match[3]}年${ENGLISH_MONTHS.get(match[1])}月${Number(match[2])}日 ${match[4]}`;
  }

  function localizeSaveTimer(value) {
    const parts = canonical(value).split(/\s*\|\s*/u);
    if (parts.length === 1 && !/\((?:local|cloud)\)$/iu.test(parts[0])) return localizeDuration(parts[0]);
    const localized = [];
    for (const part of parts) {
      const match = /^(.*?)\s+\((local|cloud)\)$/iu.exec(part);
      if (!match) return value;
      const label = match[2].toLocaleLowerCase("en-US") === "local" ? "本地" : "云端";
      localized.push(`${label} ${localizeDuration(match[1])}`);
    }
    return localized.join("｜");
  }

  function localizeDimensionCode(value) {
    const match = /^(AD|ID|TD)(?: ([1-8]))?$/u.exec(canonical(value));
    if (!match) return value;
    const dimensionType = {
      AD: "反物质维度",
      ID: "无限维度",
      TD: "时间维度"
    }[match[1]];
    return match[2] ? `第 ${match[2]} ${dimensionType}` : dimensionType;
  }

  function transformCapture(value, transform) {
    switch (transform) {
      // Some structured-help placeholders are protocol identifiers rather
      // than prose. Keeping them byte-for-byte intact prevents the ordinary
      // vocabulary catalogue from partially translating a value such as a
      // save-file header while still allowing neighboring dynamic prose to be
      // localized recursively.
      case "preserve": return value;
      case "translate": return translateWithScope(value, false);
      case "duration": return localizeDuration(value);
      case "dateTime": return localizeDateTime(value);
      case "saveTimer": return localizeSaveTimer(value);
      case "termList": return TERM_LIST.get(canonical(value)) ?? value;
      case "matterVerb": return MATTER_VERBS.get(canonical(value)) ?? value;
      case "matterObject": return MATTER_OBJECTS.get(canonical(value)) ?? value;
      case "theme": return THEMES.get(canonical(value)) ?? value;
      case "notation": return NOTATIONS.get(canonical(value)) ?? value;
      case "sidebarResource": return SIDEBAR_RESOURCES.get(canonical(value)) ?? value;
      case "dimensionCode": return localizeDimensionCode(value);
      case "ordinal": {
        const match = /^([1-9][0-9]*)(?:st|nd|rd|th)$/iu.exec(canonical(value));
        return match ? `第 ${match[1]}` : value;
      }
      default: return value;
    }
  }

  function translateStructuredCapture(value) {
    if (typeof value !== "string" || !HAS_LATIN.test(value)) return value;

    // Conditional H2P expressions inject trusted fragments into a larger
    // reviewed article template. Prefer a complete rule for the fragment; if
    // none exists, translate its individual text runs without touching tags.
    // This is deliberately used only for captures owned by structured rules,
    // so user-entered names in ordinary UI templates remain untouched.
    const complete = translateCore(value, false, false, /<[^>]+>/u.test(value));
    if (complete !== value) return complete;
    if (!/<[^>]+>/u.test(value)) return translateWithScope(value, false);

    // Optional H2P branches are commonly emitted as complete <br>-terminated
    // lines. Translate each such trusted fragment before falling back to its
    // individual text runs; this retains the context needed for entries such
    // as "IP - Infinity Point" instead of translating isolated words.
    const lineFragments = value.match(/[\s\S]*?<br\s*\/?>|[\s\S]+$/giu) ?? [value];
    return lineFragments.map(fragment => {
      const translated = translateCore(fragment, false, false, /<[^>]+>/u.test(fragment));
      if (translated !== fragment) return translated;
      return fragment.replace(/(^|>)([^<]+)(?=<|$)/gu, (match, boundary, text) =>
        boundary + translateWithScope(text, false));
    }).join("");
  }

  function applyTemplate(rule, capturedValues) {
    const values = new Map();
    for (let index = 0; index < rule.captures.length; index += 1) {
      const placeholder = rule.captures[index];
      if (!values.has(placeholder)) {
        const configuredTransform = rule.captureTransforms?.[placeholder];
        const captured = configuredTransform
          ? transformCapture(capturedValues[index], configuredTransform)
          : (rule.structured ? translateStructuredCapture(capturedValues[index]) : capturedValues[index]);
        values.set(placeholder, captured);
      }
    }
    return rule.replacement.replace(PLACEHOLDER, (_placeholder, index) => values.get(Number(index)) ?? "");
  }

  // Standard notation builds suffixes from this fixed vocabulary. Matching the
  // same vocabulary lets typed placeholders accept values such as "1.23 Qa"
  // without also accepting ordinary UI prose such as "1 Max".
  const STANDARD_NOTATION_PARTS = [
    "Sx", "Sp", "Oc", "No", "Qa", "Qt",
    "Dc", "Vg", "Tg", "Qd", "Qi", "Se", "St", "Og", "Nn",
    "Ce", "Dn", "Tc", "Qe", "Qu", "Sc", "Si", "Oe", "Ne",
    "MI", "MC", "NA", "PC", "FM", "AT", "ZP",
    "K", "M", "B", "T", "U", "D", "O", "N"
  ].sort((left, right) => right.length - left.length);

  function isStandardNotationWord(word) {
    let remaining = word;
    while (remaining) {
      const part = STANDARD_NOTATION_PARTS.find(candidate => remaining.startsWith(candidate));
      if (!part) return false;
      remaining = remaining.slice(part.length);
    }
    return true;
  }

  // Numeric captures deliberately accept a union of formats emitted by the
  // game's notation library instead of arbitrary text containing a digit.
  // This is conservative: an unfamiliar novelty notation stays English rather
  // than letting a weak template consume unrelated UI prose.
  const DIGITS = String.raw`(?:[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+)`;
  const DECIMAL = String.raw`(?:${DIGITS}(?:\.[0-9]+)?|\.[0-9]+)`;
  const SIGNED = String.raw`[+\-\u2212]?${DECIMAL}`;
  const DECORATED = String.raw`[×^]?${SIGNED}`;
  const PLAIN_NUMERIC = new RegExp(`^${DECORATED}%?$`, "u");
  const SCI_NUMERIC = new RegExp(`^${DECORATED}(?:[eE][+\\-\\u2212]?${DECIMAL})+%?$`, "u");
  const LOG_NUMERIC = new RegExp(`^[×^]?[+\\-\\u2212]?[eE]+${DECIMAL}%?$`, "u");
  const LETTERS_NUMERIC = new RegExp(`^${DECORATED}[a-z]+%?$`, "u");
  const IMPERIAL_NUMERIC = new RegExp(`^${DECORATED}(?:pL|nL|μL)%?$`, "u");
  const INFINITY_NUMERIC = new RegExp(
    `^[×^]?[+\\-\\u2212]?(?:(?:${DECIMAL})?∞|Infinity|Infinite|Infinitus|Primefinity\\?)%?$`,
    "u"
  );
  const STANDARD_NUMERIC = new RegExp(`^(${DECORATED}) ([A-Za-z]+(?:-[A-Za-z]+)*)%?$`, "u");
  const MIXED_EXP_STANDARD = new RegExp(
    `^(${DECORATED}[eE]${SIGNED}) ([A-Za-z]+(?:-[A-Za-z]+)*)%?$`,
    "u"
  );

  function standardSuffixIsValid(match) {
    return Boolean(match && match[2].split("-").every(isStandardNotationWord));
  }

  function numericValueIsValid(value) {
    if (!value || value.length > 128 || /[<>\r\n\t]/u.test(value)) return false;
    if (/^[0-9A-F]{8}%?$/u.test(value)) return true;
    if (PLAIN_NUMERIC.test(value) || SCI_NUMERIC.test(value) || LOG_NUMERIC.test(value) ||
        LETTERS_NUMERIC.test(value) || IMPERIAL_NUMERIC.test(value) || INFINITY_NUMERIC.test(value)) return true;
    return standardSuffixIsValid(STANDARD_NUMERIC.exec(value)) ||
      standardSuffixIsValid(MIXED_EXP_STANDARD.exec(value));
  }

  function captureValueIsValid(value, type) {
    if (!type || type === "text") return true;
    const normalized = canonical(value);
    if (type === "integer") {
      return /^(?:0|[1-9][0-9]*|[1-9][0-9]{0,2}(?:,[0-9]{3})+)$/u.test(normalized);
    }
    if (type === "numeric") {
      return numericValueIsValid(normalized);
    }
    return false;
  }

  function matchTemplateRule(rule, value, validateCaptureTypes) {
    const comparableValue = rule.caseInsensitive
      ? value.toLocaleLowerCase("en-US")
      : value;
    const segments = rule.comparableSegments;
    if (rule.captures.length === 0) return comparableValue === segments[0] ? [] : null;
    if (rule.structured) {
      const structuredSegments = rule.structuredComparableSegments;
      if (!comparableValue.startsWith(structuredSegments[0])) return null;
      const capturedValues = new Array(rule.captures.length);
      let attempts = 0;
      const captureIsValid = (captureIndex, captured) => {
        if (!validateCaptureTypes) return true;
        const placeholderIndex = rule.captures[captureIndex];
        return captureValueIsValid(captured, rule.captureTypes?.[placeholderIndex]);
      };

      // Structured help templates may contain several adjacent conditional
      // expressions which legitimately render as empty strings. Match against
      // the next substantive HTML/text anchor and preserve an adjacent run as
      // one combined capture. Reviewed H2P targets keep capture order, so this
      // reconstructs the same dynamic block without exponential backtracking.
      const visitStructured = (captureIndex, cursor) => {
        attempts += 1;
        if (attempts > 4096) return null;
        if (captureIndex === rule.captures.length) {
          return cursor === comparableValue.length ? capturedValues.slice() : null;
        }

        let anchorIndex = captureIndex + 1;
        while (anchorIndex < structuredSegments.length && !structuredSegments[anchorIndex]) anchorIndex += 1;
        const nextCaptureIndex = Math.min(anchorIndex, rule.captures.length);
        const groupEnd = nextCaptureIndex - 1;
        if (groupEnd > captureIndex && !rule.captureOrderPreserved) return null;

        const tryCapture = (end, nextCursor) => {
          const captured = value.slice(cursor, end).trim();
          if (!captureIsValid(captureIndex, captured)) return null;
          capturedValues[captureIndex] = captured;
          for (let index = captureIndex + 1; index <= groupEnd; index += 1) {
            if (!captureIsValid(index, "")) return null;
            capturedValues[index] = "";
          }
          return visitStructured(nextCaptureIndex, nextCursor);
        };

        if (anchorIndex === structuredSegments.length) {
          return tryCapture(comparableValue.length, comparableValue.length);
        }

        const anchor = structuredSegments[anchorIndex];
        let end = comparableValue.indexOf(anchor, cursor);
        while (end !== -1) {
          const result = tryCapture(end, end + anchor.length);
          if (result) return result;
          end = comparableValue.indexOf(anchor, end + 1);
        }
        return null;
      };

      return visitStructured(0, structuredSegments[0].length);
    }
    if (!comparableValue.startsWith(segments[0])) return null;

    const capturedValues = new Array(rule.captures.length);
    let attempts = 0;
    const captureIsValid = (captureIndex, captured) => {
      if (!validateCaptureTypes) return true;
      const placeholderIndex = rule.captures[captureIndex];
      return captureValueIsValid(captured, rule.captureTypes?.[placeholderIndex]);
    };

    // Match static segments in order instead of constructing one large RegExp.
    // Electron 10's V8 can overflow its regular-expression stack on multi-KB
    // help templates. This bounded segment matcher is linear for normal rules,
    // supports the rare ambiguous segment through limited backtracking, and
    // fails closed rather than blocking or terminating the translation runtime.
    const visit = (captureIndex, cursor) => {
      attempts += 1;
      if (attempts > 4096) return null;
      const nextSegment = segments[captureIndex + 1];
      const isLastCapture = captureIndex === rule.captures.length - 1;

      if (isLastCapture) {
        const end = nextSegment
          ? (comparableValue.endsWith(nextSegment) ? comparableValue.length - nextSegment.length : -1)
          : comparableValue.length;
        if (end <= cursor) return null;
        const captured = value.slice(cursor, end);
        if (!captureIsValid(captureIndex, captured)) return null;
        capturedValues[captureIndex] = captured;
        return capturedValues.slice();
      }

      if (!nextSegment) {
        for (let end = cursor + 1; end < comparableValue.length; end += 1) {
          const captured = value.slice(cursor, end);
          if (!captureIsValid(captureIndex, captured)) continue;
          capturedValues[captureIndex] = captured;
          const result = visit(captureIndex + 1, end);
          if (result) return result;
        }
        return null;
      }

      let end = comparableValue.indexOf(nextSegment, cursor + 1);
      while (end !== -1) {
        const captured = value.slice(cursor, end);
        if (captureIsValid(captureIndex, captured)) {
          capturedValues[captureIndex] = captured;
          const result = visit(captureIndex + 1, end + nextSegment.length);
          if (result) return result;
        }
        end = comparableValue.indexOf(nextSegment, end + 1);
      }
      return null;
    };

    return visit(0, segments[0].length);
  }

  function candidatePatterns(value, structuredOnly) {
    const candidates = new Set(unbucketedPatterns);
    const lowered = value.toLocaleLowerCase("en-US");
    const seenKeys = new Set();
    for (let index = 0; index <= lowered.length - 3; index += 1) {
      const key = lowered.slice(index, index + 3);
      if (!/^[a-z0-9'-]{3}$/u.test(key) || seenKeys.has(key)) continue;
      seenKeys.add(key);
      const bucket = patternBuckets.get(key);
      if (bucket) for (const rule of bucket) candidates.add(rule);
    }
    return [...candidates]
      .filter(rule => !structuredOnly || rule.structured)
      .sort((left, right) => left.priority - right.priority);
  }

  function isKnownTranslatedTarget(value) {
    if (!HAS_HAN.test(value)) return false;
    const normalized = canonicalForMatching(value);
    if (canonicalTargets.has(normalized)) return true;
    const candidates = new Set(unbucketedTargetPatterns);
    const lowered = normalized.toLocaleLowerCase("zh-CN");
    for (let index = 0; index <= lowered.length - 3; index += 1) {
      const bucket = targetPatternBuckets.get(lowered.slice(index, index + 3));
      if (bucket) for (const rule of bucket) candidates.add(rule);
    }
    return [...candidates].some(rule => matchTemplateRule(rule, normalized, false) !== null);
  }

  function translateCore(core, allowFragments = true, allowNewsOnly = false, structuredOnly = false) {
    const normalized = canonicalForMatching(core);
    const normalizedSource = canonicalSource(core);
    if (!allowNewsOnly && newsOnlyCanonical.has(normalizedSource)) return core;
    const direct = catalogue.exact[core];
    if (direct !== undefined) {
      counters.exact += 1;
      return direct;
    }

    const normalizedExact = canonicalExact.get(normalizedSource);
    if (normalizedExact !== undefined) {
      counters.exact += 1;
      return normalizedExact;
    }

    // Each template rule is indexed by a trigram from its longest static
    // English word. Trigrams remain discoverable even when a dynamic value is
    // concatenated directly onto that word, while still reducing frequent UI
    // updates from roughly 1,300 regex attempts to a small candidate set.
    const candidates = candidatePatterns(normalized, structuredOnly);
    if (!allowNewsOnly) {
      // A news-scoped rule owns its complete source shape. If global text
      // happens to match it, fail closed instead of falling through to a more
      // generic global template or fragment rule.
      for (const rule of candidates) {
        if (!rule.newsOnly) continue;
        if (matchTemplateRule(rule, normalized, true) !== null) return core;
      }
    }
    for (const rule of candidates) {
      if (rule.newsOnly && !allowNewsOnly) continue;
      const capturedValues = matchTemplateRule(rule, normalized, true);
      if (!capturedValues) continue;
      counters.pattern += 1;
      return applyTemplate(rule, capturedValues);
    }

    // A mixed-language source can legitimately contain user-provided Chinese
    // inside a dynamic placeholder, so exact/template matching runs first.
    // If no complete rule matched, do not apply broad fragments to a string
    // which already contains Chinese; this keeps translated output stable.
    if (!allowFragments || HAS_HAN.test(core)) return core;

    // Fragment replacement is intentionally a final fallback. It handles
    // dynamic labels such as "1e400 Infinity Points" while exact and template
    // translations retain priority for complete sentences.
    let fragmented = core;
    for (const rule of fragmentRules) fragmented = fragmented.replace(rule.expression, rule.replacement);
    if (fragmented !== core) {
      counters.fragment += 1;
      return fragmented;
    }
    return core;
  }

  function translateWithScope(value, allowNewsOnly) {
    if (typeof value !== "string" || !HAS_LATIN.test(value)) return value;
    const leading = value.match(/^\s*/u)?.[0] ?? "";
    const trailing = value.match(/\s*$/u)?.[0] ?? "";
    const coreEnd = value.length - trailing.length;
    const core = value.slice(leading.length, coreEnd);
    if (!core) return value;
    if (isKnownTranslatedTarget(core)) return value;
    const translated = translateCore(core, true, allowNewsOnly);
    if (translated === core && untranslatedSamples.size < 500 && !HAS_HAN.test(core)) {
      untranslatedSamples.add(canonical(core).slice(0, 300));
    }
    return translated === core ? value : leading + translated + trailing;
  }

  function translate(value) {
    return translateWithScope(value, false);
  }

  function translateNews(value) {
    return translateWithScope(value, true);
  }

  function translateStructured(value) {
    if (typeof value !== "string" || !HAS_LATIN.test(value)) return value;
    return translateCore(value, false, false, true);
  }

  function localizeMultiplierDisplayValue(value, sourceName = "") {
    const normalized = canonical(value);
    if (!normalized) return normalized;

    const parenthetical = /^\(([\s\S]*)\)$/u.exec(normalized);
    if (parenthetical) {
      const dimensionCode = localizeDimensionCode(parenthetical[1]);
      const localizedInner = dimensionCode !== parenthetical[1]
        ? dimensionCode
        : localizeMultiplierDisplayValue(parenthetical[1], sourceName);
      return `（${localizedInner}）`;
    }

    const perSecondOnDimensions = /^(.+?)\/sec on (.+?) Dimensions?(\s*➜\s*.+)?$/iu.exec(normalized);
    if (perSecondOnDimensions) {
      const arrow = perSecondOnDimensions[3] ? ` ${canonical(perSecondOnDimensions[3])}` : "";
      return `${perSecondOnDimensions[1]} 次/秒，作用于 ${perSecondOnDimensions[2]} 个维度${arrow}`;
    }

    const perSecond = /^(.+?)\/sec$/iu.exec(normalized);
    if (perSecond) {
      return /tickspeed/iu.test(sourceName) ? `${perSecond[1]} 次/秒` : `${perSecond[1]}/秒`;
    }

    const total = /^(.+?) Total$/iu.exec(normalized);
    if (total) return `总计 ${total[1]}`;

    const strength = /^(.+?),\s*(.+?) strength$/iu.exec(normalized);
    if (strength) return `${strength[1]} 个，强度 ${strength[2]}`;
    if (/^All Galaxy strength \/2$/iu.test(normalized)) return "所有星系强度 ÷2";

    // These compact values are emitted by late-game multiplier entries. Keep
    // the abbreviation handling scoped to this panel so formulae such as
    // log(AM) and log(IP) retain the notation used by the game.
    const dimensionAmount = /^(AD|ID|TD) ([1-8]),\s*(.+)$/u.exec(normalized);
    if (dimensionAmount && numericValueIsValid(dimensionAmount[3])) {
      return `${localizeDimensionCode(`${dimensionAmount[1]} ${dimensionAmount[2]}`)}：${dimensionAmount[3]}`;
    }
    const resourceAmount = /^(.+?)\s+(AM|IP|EP)$/u.exec(normalized);
    if (resourceAmount && numericValueIsValid(resourceAmount[1])) {
      const resourceName = {
        AM: "反物质",
        IP: "无限点数",
        EP: "永恒点数"
      }[resourceAmount[2]];
      return `${resourceAmount[1]} ${resourceName}`;
    }

    // displayOverride returns these finite states instead of a numeric value.
    // Explicit entries avoid exposing a broad global rule such as "Set to".
    const fixedDisplay = {
      "Cannot Crunch": "尚无法进行大坍缩",
      "Cannot Eternity": "尚无法进行永恒",
      "Set to 0 (storing real time)": "设为 0（正在储存现实时间）"
    }[normalized];
    if (fixedDisplay) return fixedDisplay;

    return normalized
      .replace(/\(current\)/giu, "（当前）")
      .replace(/\(average\)/giu, "（平均）")
      .replace(/\(fixed\)/giu, "（固定）")
      .replace(/\(storing real time\)/giu, "（正在储存现实时间）")
      .replace(/^Exponent/iu, "指数");
  }

  function localizeMultiplierNamedBody(value) {
    const normalized = canonical(value);
    // Entry names may contain their own parentheses. Starting from the final
    // delimiter preserves the longest translated name and treats only the
    // remaining parenthetical group as the dynamic display value.
    const boundaries = [];
    let boundary = normalized.indexOf(" (");
    while (boundary !== -1) {
      boundaries.push(boundary);
      boundary = normalized.indexOf(" (", boundary + 2);
    }
    // A single parenthetical group may be part of a reviewed name, for example
    // "Tickspeed (EC7)" or "Achievement 36 (AD)". Prefer its complete rule;
    // entries with a second group still split from the end so the final group
    // remains the dynamic display value.
    if (boundaries.length <= 1) {
      const completeTranslation = translateCore(normalized, false);
      if (completeTranslation !== normalized) return completeTranslation;
    }
    for (let index = boundaries.length - 1; index >= 0; index -= 1) {
      const splitAt = boundaries[index];
      const sourceName = normalized.slice(0, splitAt);
      const localizedName = translateCore(sourceName);
      if (localizedName === sourceName) continue;
      const displayValue = normalized.slice(splitAt + 1);
      return `${localizedName}${localizeMultiplierDisplayValue(displayValue, sourceName)}`;
    }
    const completeTranslation = translateCore(normalized, false);
    if (completeTranslation !== normalized) return completeTranslation;
    return value;
  }

  function localizeMultiplierBreakdown(value) {
    const normalized = canonical(value);
    const percentageEntry = /^([~<]?[^:\s]+%):\s*(.+)$/u.exec(normalized);
    if (percentageEntry) {
      const localizedBody = localizeMultiplierNamedBody(percentageEntry[2]);
      if (localizedBody !== percentageEntry[2]) return `${percentageEntry[1]}：${localizedBody}`;
      return value;
    }

    const separator = normalized.indexOf(": ");
    if (separator <= 0) return value;
    const sourceName = normalized.slice(0, separator);
    const localizedName = translateCore(sourceName);
    if (localizedName === sourceName) return value;
    const displayValue = normalized.slice(separator + 2);
    return `${localizedName}：${localizeMultiplierDisplayValue(displayValue, sourceName)}`;
  }

  function translateContextualValue(value, parent) {
    const leading = value.match(/^\s*/u)?.[0] ?? "";
    const trailing = value.match(/\s*$/u)?.[0] ?? "";
    const core = value.slice(leading.length, value.length - trailing.length);
    if (!core) return value;

    // Theme and sidebar-resource dropdowns share the same CSS class in the
    // game. Their finite name sets do not overlap, so a pair of constrained
    // dictionaries localizes both without publishing risky global entries
    // such as "Standard" or "Dark".
    if (parent.closest?.(".c-select-theme__item")) {
      const replacement = THEMES.get(canonical(core)) ?? SIDEBAR_RESOURCES.get(canonical(core));
      if (replacement !== undefined) return leading + replacement + trailing;
    }
    if (parent.closest?.(".c-select-notation__item")) {
      const replacement = NOTATIONS.get(canonical(core));
      if (replacement !== undefined) return leading + replacement + trailing;
    }

    // The Infinity Power summary is intentionally split across several text
    // nodes and value spans. Translating those fragments globally produced a
    // grammatically reversed sentence, so preserve the DOM and reorder only
    // the connective wording within this specific summary.
    const infinitySummary = parent.closest?.(".l-infinity-dim-tab") && parent.closest?.("p");
    const infinitySummaryText = canonical(infinitySummary?.textContent ?? "");
    const isInfinityPowerSummary = /(?:Infinity Power|无限之力)/iu.test(infinitySummaryText) &&
      /(?:multiplier on all|倍加成，作用于所有)/iu.test(infinitySummaryText);
    if (isInfinityPowerSummary) {
      const summaryParts = {
        "increased by": "按",
        translated: "经转换",
        "multiplier on all": "倍加成，作用于所有",
        "Antimatter Dimensions.": "反物质维度。",
        "Time Dimensions due to Eternity Challenge 9.": "时间维度（永恒挑战 9）。"
      };
      if (core === "to a") {
        const connector = /(?:translated|经转换)/iu.test(infinitySummaryText) ? "后产生" : "次方计算，产生";
        return leading + connector + trailing;
      }
      if (summaryParts[core]) return leading + summaryParts[core] + trailing;
    }

    // Achievement tooltips concatenate a localized database name and its
    // numeric ID into one text node. Translate only the name through the
    // existing reviewed catalogue, then use Chinese full-width parentheses.
    if (parent.closest?.(".o-achievement__tooltip__name")) {
      const match = /^(.*) \((S?[0-9]+)\)$/u.exec(canonical(core));
      if (match) {
        const localizedName = translate(match[1]);
        if (localizedName !== match[1]) return `${leading}${localizedName}（${match[2]}）${trailing}`;
      }
    }

    // Vue concatenates the fixed reward label and the dynamic achievement
    // reward into one node. Split only inside achievement tooltips so all
    // reviewed reward templates can be reused without a risky global prefix.
    if (parent.closest?.(".o-achievement__tooltip__reward")) {
      const match = /^Reward:\s*([\s\S]+)$/iu.exec(canonical(core));
      if (match) {
        const localizedReward = translate(match[1]);
        if (localizedReward !== match[1]) return `${leading}奖励：${localizedReward}${trailing}`;
      }
    }

    if (parent.closest?.(".c-multiplier-entry-container")) {
      const localizedBreakdown = localizeMultiplierBreakdown(core);
      if (localizedBreakdown !== core) return `${leading}${localizedBreakdown}${trailing}`;
    }

    // Statistics renders the predicate after an optional <span>, leaving a
    // tiny "is N." text node. Restrict this otherwise-weak shape to the stats
    // panel instead of exposing it as a global catalogue rule.
    if (parent.closest?.(".c-stats-tab-general")) {
      const match = /^is (.+)\.$/iu.exec(canonical(core));
      if (match && numericValueIsValid(match[1])) return `${leading}为 ${match[1]}。${trailing}`;
    }
    return value;
  }

  function isExcluded(element) {
    return Boolean(excludedSelector && element?.closest?.(excludedSelector));
  }

  function isNewsElement(element) {
    return Boolean(element?.closest?.(".c-news-ticker"));
  }

  function hasStableStructuredContainer(element) {
    let current = element;
    while (current) {
      const expected = translatedStructuredHtml.get(current);
      if (expected !== undefined) {
        if (current.innerHTML === expected) return true;
        translatedStructuredHtml.delete(current);
      }
      current = current.parentElement;
    }
    return false;
  }

  function translateTextNode(node) {
    const parent = node.parentElement;
    if (!parent || isExcluded(parent) || hasStableStructuredContainer(parent)) return;
    const original = node.nodeValue;
    const contextual = translateContextualValue(original, parent);
    const translated = contextual !== original
      ? contextual
      : (isNewsElement(parent) ? translateNews(original) : translate(original));
    if (translated === original) return;
    node.nodeValue = translated;
    counters.textNodes += 1;
  }

  function translateAttributes(element) {
    if (isExcluded(element) || hasStableStructuredContainer(element)) return;
    const translateElementValue = isNewsElement(element) ? translateNews : translate;
    for (const name of TRANSLATABLE_ATTRIBUTES) {
      if (!element.hasAttribute(name)) continue;
      const original = element.getAttribute(name);
      const translated = translateElementValue(original);
      if (translated === original) continue;
      element.setAttribute(name, translated);
      counters.attributes += 1;
    }
    if (element instanceof HTMLInputElement && ["button", "submit", "reset"].includes(element.type)) {
      const translated = translateElementValue(element.value);
      if (translated !== element.value) {
        element.value = translated;
        counters.attributes += 1;
      }
    }
  }

  function applyStructuredTextSafely(element, translatedHtml) {
    if (typeof document.createElement !== "function" || !element.childNodes) return false;
    const template = document.createElement("template");
    if (!template?.content) return false;
    template.innerHTML = translatedHtml;

    const textUpdates = [];
    const meaningfulChildren = node => Array.from(node.childNodes ?? []).filter(child =>
      child.nodeType !== Node.TEXT_NODE || child.nodeValue.trim() !== "");
    const collectTextUpdates = (source, target) => {
      if (source.nodeType !== target.nodeType) return false;
      if (source.nodeType === Node.ELEMENT_NODE && source.tagName !== target.tagName) return false;

      // Formatting-only whitespace around <br> and block tags is not part of
      // the rendered prose and may differ between source templates. Ignore it
      // for alignment while still requiring every meaningful node and element
      // to have the same order and type.
      const sourceChildren = meaningfulChildren(source);
      const targetChildren = meaningfulChildren(target);
      if (sourceChildren.length !== targetChildren.length) return false;
      for (let index = 0; index < sourceChildren.length; index += 1) {
        if (!collectTextUpdates(sourceChildren[index], targetChildren[index])) return false;
      }
      if (source.nodeType === Node.TEXT_NODE && source.nodeValue !== target.nodeValue) {
        textUpdates.push([source, target.nodeValue]);
      }
      return true;
    };

    const sourceChildren = meaningfulChildren(element);
    const targetChildren = meaningfulChildren(template.content);
    if (sourceChildren.length !== targetChildren.length) return false;
    for (let index = 0; index < sourceChildren.length; index += 1) {
      if (!collectTextUpdates(sourceChildren[index], targetChildren[index])) return false;
    }
    for (const [node, value] of textUpdates) node.nodeValue = value;
    return textUpdates.length > 0;
  }

  function translateStructuredHtml(element) {
    if (isExcluded(element) || !element.childElementCount || typeof element.innerHTML !== "string") return false;
    const original = element.innerHTML;
    const previous = translatedStructuredHtml.get(element);
    if (previous !== undefined) {
      if (previous === original) return true;
      translatedStructuredHtml.delete(element);
    }
    if (hasStableStructuredContainer(element.parentElement)) return false;
    const isHelpArticle = element.id === "h2p-body" && element.classList?.contains("c-h2p-body");
    const maximumLength = isHelpArticle ? 100000 : 20000;
    if (original.length > maximumLength || !HAS_LATIN.test(original) || !/<[^>]+>/u.test(original)) return false;

    // Vue's v-html and direct innerHTML assignments split one source string
    // into several DOM nodes. Match the serialized fragment as a unit before
    // falling back to node-by-node translation. The translated fragment is
    // parsed separately and must have the same node/tag shape; only existing
    // text nodes are changed. This preserves Vue instances, form state, and
    // click handlers instead of replacing a live subtree through innerHTML.
    const translated = translateCore(original, false, isNewsElement(element), true);
    if (translated === original) return false;

    // The H2P body is the game's dedicated v-html container. Its descendants
    // are static prose generated from trusted game data and do not contain Vue
    // components or event handlers. Replacing this one container is therefore
    // both safe and necessary: several reviewed Chinese articles intentionally
    // use a different whitespace/text-node layout from the English source.
    // All other structured UI keeps the stricter identity-preserving path.
    if (isHelpArticle) {
      element.innerHTML = translated;
      translatedStructuredHtml.set(element, element.innerHTML);
      counters.html += 1;
      return true;
    }
    if (!applyStructuredTextSafely(element, translated)) return false;
    // Chromium normalizes attribute quoting and optional tags when reading
    // innerHTML back. Store that serialized value rather than the input text.
    translatedStructuredHtml.set(element, element.innerHTML);
    counters.html += 1;
    return true;
  }

  function translateSubtree(root) {
    if (!root) return;
    if (root.nodeType === Node.TEXT_NODE) {
      translateTextNode(root);
      return;
    }
    if (root.nodeType !== Node.ELEMENT_NODE && root.nodeType !== Node.DOCUMENT_NODE &&
        root.nodeType !== Node.DOCUMENT_FRAGMENT_NODE) return;
    if (root.nodeType === Node.ELEMENT_NODE && isExcluded(root)) return;

    if (root.nodeType === Node.ELEMENT_NODE) {
      if (translateStructuredHtml(root)) return;
      translateAttributes(root);
    }
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT);
    let current = walker.nextNode();
    while (current) {
      if (current.nodeType === Node.TEXT_NODE) translateTextNode(current);
      else {
        if (!translateStructuredHtml(current)) translateAttributes(current);
      }
      current = walker.nextNode();
    }
  }

  const pending = new Set();
  let flushScheduled = false;
  function flush() {
    flushScheduled = false;
    // MutationObserver can report both a container and many descendants in one
    // batch. Scan only the highest pending nodes so a large Vue update is not
    // translated repeatedly in the same frame.
    const nodes = [...pending].filter(node => {
      let parent = node.parentNode;
      while (parent) {
        if (pending.has(parent)) return false;
        parent = parent.parentNode;
      }
      return true;
    });
    pending.clear();
    for (const node of nodes) translateSubtree(node);
  }

  function schedule(node) {
    if (node) pending.add(node);
    if (flushScheduled) return;
    flushScheduled = true;
    // A frame callback batches high-frequency game updates and yields control
    // back to Vue and the game loop. A microtask here can continuously outrun
    // rendering when translation itself produces observer records.
    if (typeof globalThis.requestAnimationFrame === "function") {
      globalThis.requestAnimationFrame(flush);
    }
    else {
      globalThis.setTimeout(flush, 0);
    }
  }

  function install() {
    document.documentElement.lang = "zh-CN";
    document.title = "反物质维度";

    // Translate only rendered content. GameDatabase is a large live object
    // graph with framework-owned references; synchronously walking and
    // rewriting it blocks the renderer during startup and can alter callbacks.
    // The initial scan plus observer cover the same player-facing text without
    // touching game state or event handlers.
    translateSubtree(document.documentElement);

    const observer = new MutationObserver(mutations => {
      for (const mutation of mutations) {
        if (mutation.type === "characterData") schedule(mutation.target);
        else if (mutation.type === "attributes") schedule(mutation.target);
        else {
          // Scheduling the target preserves the original v-html fragment as
          // one translatable unit; added nodes alone have already lost it.
          schedule(mutation.target);
        }
      }
    });
    observer.observe(document.documentElement, {
      subtree: true,
      childList: true,
      characterData: true,
      attributes: true,
      attributeFilter: TRANSLATABLE_ATTRIBUTES
    });

    globalThis.ADChinesePatch = Object.freeze({
      version: catalogue.patchVersion,
      locale: catalogue.locale,
      catalogueStats: catalogue.stats,
      counters,
      translate,
      translateNews,
      translateStructured,
      rescan: () => translateSubtree(document.documentElement),
      untranslated: () => [...untranslatedSamples].filter(Boolean).sort()
    });
    console.info(`[AD Zh-CN] Patch ${catalogue.patchVersion} loaded`, catalogue.stats);
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", install, { once: true });
  else install();
})();
