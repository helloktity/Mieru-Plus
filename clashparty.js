// 倍率过滤：true 过滤名称明确标注 >1 倍率的节点；false 保留全部。
// 未标注倍率、1倍及以下保留。修改后重新应用覆写。
const FILTER_HIGH_MULTIPLIER = true;

// Clash Party / Mihomo JavaScript 覆写版本
// 基于 clash verge备份脚本.js；保留原有业务分组与规则。
// 导入：覆写 -> 新建/导入 JavaScript -> 为订阅启用。
// 使用本脚本 DNS 时，关闭软件自身的 DNS 覆写，避免覆盖脚本 DNS。
// TUN 和系统代理由 Clash Party 界面管理，本脚本不强制切换。

// 国内DNS服务器
const domesticNameservers = [
  "https://223.5.5.5/dns-query", // 阿里DoH
  "https://doh.pub/dns-query" // 腾讯DoH
];
// 国外DNS服务器
const foreignNameservers = [
  "https://1.1.1.1/dns-query", // CloudflareDNS
  "https://8.8.8.8/dns-query", // GoogleDNS
];
// DNS配置
const dnsConfig = {
  "enable": true,
  "listen": ":53",
  "ipv6": false,
  "prefer-h3": false, // respect-rules 开启时不优先使用 HTTP/3
  "respect-rules": true,
  "use-system-hosts": false,
  "cache-algorithm": "arc",
  "enhanced-mode": "fake-ip",
  "fake-ip-range": "198.18.0.1/16",
  "fake-ip-filter": [
    "+.lan",
    "+.local",
    "+.msftconnecttest.com",
    "+.msftncsi.com",
    "localhost.ptlogin2.qq.com",
    "localhost.sec.qq.com",
    "+.in-addr.arpa",
    "+.ip6.arpa",
    "time.*.com",
    "time.*.gov",
    "pool.ntp.org",
    "localhost.work.weixin.qq.com",
    "+.srv.nintendo.net",       // Nintendo Switch 联机检测
    "+.stun.*.*",               // STUN 穿透
    "+.stun.*.*.*",
    "dns.msftncsi.com",         // Windows 网络状态检测
    "www.msftconnecttest.com"
  ],
  "default-nameserver": ["223.5.5.5", "119.29.29.29"], // 更换更稳定的底层备用 DNS
  "nameserver": [...foreignNameservers],
  "proxy-server-nameserver": [...domesticNameservers],
  "direct-nameserver": [...domesticNameservers],
  "nameserver-policy": {
    "geosite:private,cn": domesticNameservers
  }
};
// 规则集通用配置
const ruleProviderCommon = {
  "type": "http",
  "format": "yaml",
  "interval": 86400
};
// 规则集配置
const ruleProviders = {
  "reject": {
    ...ruleProviderCommon,
    "behavior": "domain",
    "url": "https://fastly.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/reject.txt",
    "path": "./ruleset/loyalsoldier/reject.yaml"
  },
  "icloud": {
    ...ruleProviderCommon,
    "behavior": "domain",
    "url": "https://fastly.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/icloud.txt",
    "path": "./ruleset/loyalsoldier/icloud.yaml"
  },
  "apple": {
    ...ruleProviderCommon,
    "behavior": "domain",
    "url": "https://fastly.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/apple.txt",
    "path": "./ruleset/loyalsoldier/apple.yaml"
  },
  "google": {
    ...ruleProviderCommon,
    "behavior": "domain",
    "url": "https://fastly.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/google.txt",
    "path": "./ruleset/loyalsoldier/google.yaml"
  },
  "proxy": {
    ...ruleProviderCommon,
    "behavior": "domain",
    "url": "https://fastly.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/proxy.txt",
    "path": "./ruleset/loyalsoldier/proxy.yaml"
  },
  "direct": {
    ...ruleProviderCommon,
    "behavior": "domain",
    "url": "https://fastly.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/direct.txt",
    "path": "./ruleset/loyalsoldier/direct.yaml"
  },
  "private": {
    ...ruleProviderCommon,
    "behavior": "domain",
    "url": "https://fastly.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/private.txt",
    "path": "./ruleset/loyalsoldier/private.yaml"
  },
  "gfw": {
    ...ruleProviderCommon,
    "behavior": "domain",
    "url": "https://fastly.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/gfw.txt",
    "path": "./ruleset/loyalsoldier/gfw.yaml"
  },
  "tld-not-cn": {
    ...ruleProviderCommon,
    "behavior": "domain",
    "url": "https://fastly.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/tld-not-cn.txt",
    "path": "./ruleset/loyalsoldier/tld-not-cn.yaml"
  },
  "telegramcidr": {
    ...ruleProviderCommon,
    "behavior": "ipcidr",
    "url": "https://fastly.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/telegramcidr.txt",
    "path": "./ruleset/loyalsoldier/telegramcidr.yaml"
  },
  "cncidr": {
    ...ruleProviderCommon,
    "behavior": "ipcidr",
    "url": "https://fastly.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/cncidr.txt",
    "path": "./ruleset/loyalsoldier/cncidr.yaml"
  },
  "lancidr": {
    ...ruleProviderCommon,
    "behavior": "ipcidr",
    "url": "https://fastly.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/lancidr.txt",
    "path": "./ruleset/loyalsoldier/lancidr.yaml"
  },
  "applications": {
    ...ruleProviderCommon,
    "behavior": "classical",
    "url": "https://fastly.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/applications.txt",
    "path": "./ruleset/loyalsoldier/applications.yaml"
  },
  "bahamut": {
    ...ruleProviderCommon,
    "behavior": "classical",
    "url": "https://fastly.jsdelivr.net/gh/xiaolin-007/clash@main/rule/Bahamut.txt",
    "path": "./ruleset/xiaolin-007/bahamut.yaml"
  },
  "YouTube": {
    ...ruleProviderCommon,
    "behavior": "classical",
    "url": "https://fastly.jsdelivr.net/gh/xiaolin-007/clash@main/rule/YouTube.txt",
    "path": "./ruleset/xiaolin-007/YouTube.yaml"
  },
  "Netflix": {
    ...ruleProviderCommon,
    "behavior": "classical",
    "url": "https://fastly.jsdelivr.net/gh/xiaolin-007/clash@main/rule/Netflix.txt",
    "path": "./ruleset/xiaolin-007/Netflix.yaml"
  },
  "Spotify": {
    ...ruleProviderCommon,
    "behavior": "classical",
    "url": "https://fastly.jsdelivr.net/gh/xiaolin-007/clash@main/rule/Spotify.txt",
    "path": "./ruleset/xiaolin-007/Spotify.yaml"
  },
  "BilibiliHMT": {
    ...ruleProviderCommon,
    "behavior": "classical",
    "url": "https://fastly.jsdelivr.net/gh/xiaolin-007/clash@main/rule/BilibiliHMT.txt",
    "path": "./ruleset/xiaolin-007/BilibiliHMT.yaml"
  },
  "AI": {
    ...ruleProviderCommon,
    "behavior": "classical",
    "url": "https://fastly.jsdelivr.net/gh/xiaolin-007/clash@main/rule/AI.txt",
    "path": "./ruleset/xiaolin-007/AI.yaml"
  },
  "TikTok": {
    ...ruleProviderCommon,
    "behavior": "classical",
    "url": "https://fastly.jsdelivr.net/gh/xiaolin-007/clash@main/rule/TikTok.txt",
    "path": "./ruleset/xiaolin-007/TikTok.yaml"
  },
};
// 规则
const rules = [
  "PROCESS-NAME,OFT.Platform.exe,全局直连",
  "DOMAIN-SUFFIX,lucidtrading.com,全局直连",
  "DOMAIN-KEYWORD,fundednext,全局直连",
  "DOMAIN-SUFFIX,rithmic.com,节点选择",
  "DOMAIN-SUFFIX,telegram.org,节点选择",
  "DOMAIN-SUFFIX,googleapis.cn,节点选择",
  "DOMAIN-SUFFIX,gstatic.com,节点选择",
  "DOMAIN-SUFFIX,xn--ngstr-lra8j.com,节点选择",
  "DOMAIN-SUFFIX,github.io,节点选择", // Github Pages
  "DOMAIN,v2rayse.com,节点选择",
  "RULE-SET,applications,全局直连",
  "RULE-SET,private,全局直连",
  "RULE-SET,reject,广告过滤",
  "RULE-SET,icloud,苹果服务",
  "RULE-SET,apple,苹果服务",
  "RULE-SET,YouTube,YouTube",
  "RULE-SET,Netflix,Netflix",
  "RULE-SET,bahamut,动画疯",
  "RULE-SET,Spotify,Spotify",
  "RULE-SET,BilibiliHMT,哔哩哔哩港澳台",
  "RULE-SET,AI,AI",
  "RULE-SET,TikTok,TikTok",
  "RULE-SET,google,谷歌服务",
  "RULE-SET,proxy,节点选择",
  "RULE-SET,gfw,节点选择",
  "RULE-SET,tld-not-cn,节点选择",
  "RULE-SET,direct,全局直连",
  "RULE-SET,lancidr,全局直连,no-resolve",
  "RULE-SET,cncidr,全局直连,no-resolve",
  "RULE-SET,telegramcidr,电报消息,no-resolve",
  "GEOSITE,CN,全局直连",
  "GEOIP,LAN,全局直连,no-resolve",
  "GEOIP,CN,全局直连,no-resolve", // 修复此处手误引入的命名错误
  "MATCH,漏网之鱼"
];
// 代理组通用配置
const groupBaseOption = {
  "interval": 300,
  "timeout": 3000,
  "url": "https://www.google.com/generate_204",
  "lazy": true,
  "max-failed-times": 3,
  "hidden": false
};

// 节点过滤正则（过滤掉含"官网/套餐/流量/异常/剩余"的节点名）
const excludeFilter = "官网|套餐|流量|异常|剩余";

// 程序入口
const main = (config) => {
  const proxyCount = config?.proxies?.length ?? 0;
  const proxyProviderCount =
    typeof config?.["proxy-providers"] === "object" ? Object.keys(config["proxy-providers"]).length : 0;
  if (proxyCount === 0 && proxyProviderCount === 0) {
    throw new Error("配置文件中未找到任何代理");
  }

  function hasHighMultiplier(name) {
    const text = String(name || "").normalize("NFKC");
    const patterns = [
      /(\d+(?:\.\d+)?)\s*倍(?:率)?/g,
      /倍率\s*[:：=]?\s*(\d+(?:\.\d+)?)/g,
      /(?:^|[^a-z0-9.])(\d+(?:\.\d+)?)\s*[x×](?=$|[^a-z0-9])/gi,
      /(?:^|[^a-z0-9])[x×]\s*(\d+(?:\.\d+)?)(?=$|[^a-z0-9.])/gi
    ];
    return patterns.some((pattern) => {
      let match;
      while ((match = pattern.exec(text)) !== null) {
        if (Number(match[1]) > 1) return true;
      }
      return false;
    });
  }


  if (FILTER_HIGH_MULTIPLIER && Array.isArray(config.proxies)) {
    config.proxies = config.proxies.filter((proxy) => !proxy || !hasHighMultiplier(proxy.name));
  }

  config["dns"] = dnsConfig;

  config["proxy-groups"] = [
    {
      ...groupBaseOption,
      "name": "节点选择",
      "type": "select",
      "include-all": true,
      "exclude-filter": excludeFilter,
      "icon": "https://fastly.jsdelivr.net/gh/clash-verge-rev/clash-verge-rev.github.io@main/docs/assets/icons/adjust.svg"
    },
    {
      ...groupBaseOption,
      "name": "谷歌服务",
      "type": "select",
      "proxies": ["节点选择", "全局直连"],
      "include-all": true,
      "icon": "https://fastly.jsdelivr.net/gh/clash-verge-rev/clash-verge-rev.github.io@main/docs/assets/icons/google.svg"
    },
    {
      ...groupBaseOption,
      "name": "YouTube",
      "type": "select",
      "proxies": ["节点选择", "全局直连"],
      "include-all": true,
      "icon": "https://fastly.jsdelivr.net/gh/clash-verge-rev/clash-verge-rev.github.io@main/docs/assets/icons/youtube.svg"
    },
    {
      ...groupBaseOption,
      "name": "Netflix",
      "type": "select",
      "proxies": ["节点选择", "全局直连"],
      "include-all": true,
      "icon": "https://fastly.jsdelivr.net/gh/xiaolin-007/clash@main/icon/netflix.svg"
    },
    {
      ...groupBaseOption,
      "name": "电报消息",
      "type": "select",
      "proxies": ["节点选择", "全局直连"],
      "include-all": true,
      "icon": "https://fastly.jsdelivr.net/gh/clash-verge-rev/clash-verge-rev.github.io@main/docs/assets/icons/telegram.svg"
    },
    {
      ...groupBaseOption,
      "name": "AI",
      "type": "select",
      "include-all": true,
      "proxies": ["节点选择"],
      "icon": "https://fastly.jsdelivr.net/gh/clash-verge-rev/clash-verge-rev.github.io@main/docs/assets/icons/chatgpt.svg"
    },
    {
      ...groupBaseOption,
      "name": "TikTok",
      "type": "select",
      "include-all": true,
      "proxies": ["节点选择"],
      "icon": "https://fastly.jsdelivr.net/gh/xiaolin-007/clash@main/icon/tiktok.svg"
    },
    {
      ...groupBaseOption,
      "name": "微软服务",
      "type": "select",
      "proxies": ["全局直连", "节点选择"],
      "include-all": true,
      "icon": "https://fastly.jsdelivr.net/gh/clash-verge-rev/clash-verge-rev.github.io@main/docs/assets/icons/microsoft.svg"
    },
    {
      ...groupBaseOption,
      "name": "苹果服务",
      "type": "select",
      "proxies": ["节点选择", "全局直连"],
      "include-all": true,
      "icon": "https://fastly.jsdelivr.net/gh/clash-verge-rev/clash-verge-rev.github.io@main/docs/assets/icons/apple.svg"
    },
    {
      ...groupBaseOption,
      "name": "动画疯",
      "type": "select",
      "proxies": ["节点选择"],
      "include-all": true,
      "filter": "(?i)台|tw",
      "icon": "https://fastly.jsdelivr.net/gh/xiaolin-007/clash@main/icon/Bahamut.svg"
    },
    {
      ...groupBaseOption,
      "name": "哔哩哔哩港澳台",
      "type": "select",
      "proxies": ["全局直连", "节点选择"],
      "include-all": true,
      "exclude-filter": excludeFilter,
      "icon": "https://fastly.jsdelivr.net/gh/xiaolin-007/clash@main/icon/bilibili.svg"
    },
    {
      ...groupBaseOption,
      "name": "Spotify",
      "type": "select",
      "proxies": ["节点选择", "全局直连"],
      "include-all": true,
      "icon": "https://fastly.jsdelivr.net/gh/xiaolin-007/clash@main/icon/spotify.svg"
    },
    {
      ...groupBaseOption,
      "name": "广告过滤",
      "type": "select",
      "proxies": ["节点选择", "REJECT", "DIRECT"],
      "icon": "https://fastly.jsdelivr.net/gh/clash-verge-rev/clash-verge-rev.github.io@main/docs/assets/icons/bug.svg"
    },
    {
      ...groupBaseOption,
      "name": "全局直连",
      "type": "select",
      "proxies": ["DIRECT", "节点选择"],
      "include-all": true,
      "icon": "https://fastly.jsdelivr.net/gh/clash-verge-rev/clash-verge-rev.github.io@main/docs/assets/icons/link.svg"
    },
    {
      ...groupBaseOption,
      "name": "全局拦截",
      "type": "select",
      "proxies": ["REJECT", "DIRECT"],
      "icon": "https://fastly.jsdelivr.net/gh/clash-verge-rev/clash-verge-rev.github.io@main/docs/assets/icons/block.svg"
    },
    {
      ...groupBaseOption,
      "name": "漏网之鱼",
      "type": "select",
      "proxies": ["节点选择", "全局直连"],
      "include-all": true,
      "exclude-filter": excludeFilter,
      "icon": "https://fastly.jsdelivr.net/gh/clash-verge-rev/clash-verge-rev.github.io@main/docs/assets/icons/fish.svg"
    }
  ];

  // 动态 proxy-provider 的节点无法在脚本执行时读取，使用组级排除表达式过滤。
  if (FILTER_HIGH_MULTIPLIER) {
    const number = "(?:0*[2-9][0-9]*(?:\\.[0-9]+)?|0*1[0-9]+(?:\\.[0-9]+)?|0*1\\.0*[1-9][0-9]*)";
    const multiplierFilter = "(?i)(?:^|[^0-9.])" + number + "\\s*(?:倍率?|[x×](?:$|[^a-z0-9]))|倍率\\s*[:：=]?\\s*" + number + "(?:$|[^0-9.])|(?:^|[^a-z0-9])[x×]\\s*" + number + "(?:$|[^0-9.])";
    config["proxy-groups"].forEach((group) => {
      if (!group["include-all"]) return;
      const previous = group["exclude-filter"];
      group["exclude-filter"] = previous ? "(?:" + previous + ")|" + multiplierFilter : multiplierFilter;
      group["empty-fallback"] = "REJECT";
    });
  }

  config["rule-providers"] = ruleProviders;
  config["rules"] = rules;

  // 安全防御与现代 UDP 协议优化
  if (config["proxies"] && Array.isArray(config["proxies"])) {
    config["proxies"].forEach(proxy => {
      if (proxy && typeof proxy === 'object') {
        // SSR / SOCKS5 等协议不支持修改 UDP 设置，跳过避免报错
        if (proxy.type === 'ssr' || proxy.type === 'socks5') {
          return;
        }
        proxy.udp = true;
        if (proxy.type === 'tuic' || proxy.type === 'hysteria2') {
          proxy['congestion-controller'] = 'bbr';
        }
      }
    });
  }

  return config;
};
