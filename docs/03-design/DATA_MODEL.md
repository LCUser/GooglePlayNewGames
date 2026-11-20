# 数据模型

- 文档编号：TECH-DATA-001
- 版本：V1.0
- 状态：Gate 4 已通过；方案获用户确认
- 更新时间：2026-11-20
- 输入基线：API-DICT-001（Gate 2 已通过）、REQ-DOC-001（V1.0）
- 审核人 / 审核日期：用户 / 2026-11-20

模型只映射已验证 API 字段；API 字段存在不代表必须在 UI 展示。API 字典对子对象字段尚未补全，因此其内部结构在实现前须以保存的脱敏验证证据或新的获准 API 验证确认，不得臆造属性。

## DTO 与领域模型

| 模型 | 字段 | 类型 / 约束 | 来源与用途 |
|---|---|---|---|
| `GameSummaryDTO` | `id` | 非空字符串 | `/new`；列表身份及详情请求键 |
|  | `title` | 非空字符串 | `/new`；列表标题 |
|  | `icon` | URL 字符串 | `/new`；列表图标资源 |
|  | `category` | 对象；保留已验证 ID / 名称 | `/new`；只接受 `GAME_PUZZLE` 或 `GAME_CASUAL` |
|  | `released` | ISO 8601 UTC 时间戳，解析为绝对时刻 | `/new`；本地日历过滤与排序 |
| `GameSummary` | `id`、`title`、`iconURL`、`categoryID`、`categoryName`、`releasedAt` | 强类型不可变领域值 | 由 DTO 验证后转换；只包含列表需要字段 |
| `GameDetailDTO` | `id`、`url`、`title`、`title_lang`、`summary`、`description`、`recent_changes`、`status`、`installs`、`rating`、`pricing`、`category`、`content_rating`、`developer`、`released`、`updated`、`version`、`android_min`、`media` | 详情接口实测字段；`recent_changes` 可为 null | `/app`；键见 API 数据字典/实测报告 |
| `GameDetail` | `id`、`title`、`summary`、`description`、`recentChanges?`、`releasedAt`，以及经批准要展示且已验证的字段 | 不可变领域值；可空值显式可选 | 详情页面模型；`url` 不进入展示模型或导航接口 |
| `CategoryID` | `GAME_PUZZLE`、`GAME_CASUAL` | 封闭枚举；未知值不可静默扩展 | Gate 3 需求基线 |
| `ReleaseDateWindow` | `startInclusive`、`endExclusive` | UTC 绝对时刻；前者含、后者不含 | 由设备本地 `Calendar` 日界转换得出 |
| `GamePageDTO` | `total`、`page`、`per`、`pages`、结果集合 | `/new` 第一页响应及服务端分页元数据 | App 仅请求 Casual 的 `page=1`、`per=100`；仅验证并使用第一页，不追取后续页 |

开发者、安装量、评分、状态、定价、内容分级及媒体等对象在 API 字典中只有容器级证据、子字段未补充。不得在 Gate 4 文档中猜测子属性或格式。若产品 UI 需要这些对象的子字段，应先确认其真实键、类型、nullability，再纳入模型。

## 解码与验证规则

- DTO 负责匹配线上键名及 API 可空字段；领域模型不暴露未经验证的任意 JSON。
- 必需字段缺失、类型不匹配、`released` 无法解析、类别不在允许集合或详情响应 ID 不匹配，均视为契约/解码错误。
- `/new` 的 `url` 虽返回，但基线禁止外部商店跳转，不放入列表展示模型。
- `/app` 的 `url` 不得提供给视图作为可点击链接；详情字段的最终展示集合需用户审核，不可因模型拥有字段而自动展示。
- `recent_changes` 可为 null；其他字段的“必有”只表示样本中出现键，不保证值非空。映射应尊重实际 nullability。
- 分类聚合后以 `id` 去重；排序以解析后的 `releasedAt` 降序，时间相同以 `id` 升序确定次序。
- 页面状态与业务实体分离：列表状态为 `loading` / `loaded([GameSummary])` / `empty` / `failed`；详情状态模型需在详情错误呈现决策确定后定稿。

更多时区边界、API UTC 日期包络和错误行为见 `TECH_DESIGN.md`。
