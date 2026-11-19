# API 数据字典

- 文档编号：API-DICT-001
- 状态：阶段 2 验证中

| 字段 | 实际类型 | 是否必有 | 含义 | 示例（脱敏） | 来源接口 | 验证状态 |
|---|---|---|---|---|---|---|
| `id` | string | 是 | 应用 ID | `sample.package` | `/new`、`/app` | 已验证 |
| `title` | string | 是 | 应用标题 | 已脱敏 | `/new`、`/app` | 已验证 |
| `url` | string | 是 | 商店 URL | 不记录 | `/new`、`/app` | 已验证；首版不展示或跳转 |
| `icon` | string | 是 | 图标 URL | 不记录 | `/new` | 已验证 |
| `developer` | object | 是 | 开发者信息 | 对象 | `/new`、`/app` | 已验证；子字段待补充 |
| `category` | object | 是 | 类别 ID 与名称；产品范围仅接受 `GAME_PUZZLE`、`GAME_CASUAL` | `GAME_PUZZLE` | `/new`、`/app` | 已验证 |
| `installs` | object | 是 | 安装量信息 | 对象 | `/new`、`/app` | 已验证；子字段待补充 |
| `rating` | object | 是 | 评分信息 | 对象 | `/new`、`/app` | 已验证；子字段待补充 |
| `free` | boolean | 是 | 是否免费 | `true` | `/new` | 已验证 |
| `price` | number | 是 | 价格值 | 数值 | `/new` | 已验证 |
| `currency` | string | 是 | 价格币种 | 字符串 | `/new` | 已验证 |
| `released` | string | 是 | 首次发布日期时间戳，UTC | `2026-11-12T23:58:52Z` | `/new`、`/app` | 已验证 |
| `updated` | string | 是 | 最近更新时间 | UTC 时间戳 | `/new`、`/app` | 已验证 |
| `removed` | boolean | 是 | 是否已下架 | 布尔值 | `/new` | 已验证 |
| `removed_seen_at` | 未确认（样本为 null） | 否 | 首次观察到下架的时间 | null | `/new` | 字段存在；非空值类型待验证 |
| `title_lang` | string | 是 | 标题语言 | 字符串 | `/app` | 已验证 |
| `summary` | string | 是 | 简介 | 已脱敏 | `/app` | 已验证 |
| `description` | string | 是 | 详情描述 | 已脱敏 | `/app` | 已验证 |
| `recent_changes` | string 或 null | 否 | 最近更新说明 | null | `/app` | 已验证 |
| `status` | object | 是 | 应用状态信息 | 对象 | `/app` | 已验证；子字段待补充 |
| `pricing` | object | 是 | 价格信息 | 对象 | `/app` | 已验证；子字段待补充 |
| `content_rating` | object | 是 | 内容分级信息 | 对象 | `/app` | 已验证；子字段待补充 |
| `version` | string | 是 | 版本 | 字符串 | `/app` | 已验证 |
| `android_min` | string | 是 | 最低 Android 版本 | 字符串 | `/app` | 已验证 |
| `media` | object | 是 | 媒体信息 | 对象 | `/app` | 已验证；子字段待补充 |

说明：字段“必有”表示样本响应中出现该键，不代表值永不为空。正式展示字段仍须按已批准需求筛选；API 返回不等于产品必须展示。
