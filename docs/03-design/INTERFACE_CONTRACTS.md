# 模块接口契约

- 文档编号：TECH-IF-001
- 版本：V1.0（Gate 4 审核稿）
- 状态：待用户审核；Gate 4 未通过
- 更新时间：2026-11-20
- 适用需求：REQ-001、REQ-002（V1.0）

以下为逻辑接口设计，不是已实现代码签名。错误类型、并发方式与具体 Swift 类型待 Gate 4 决定后由阶段 5/6 细化。

| 接口 ID | 职责 / 输入 | 输出 | 错误与并发约定 | 调用方 → 实现方 | 验证要求 |
|---|---|---|---|---|---|
| IF-001 `loadGames` | 无业务筛选输入；接收刷新时刻及设备日历/时区快照 | 完整、去重、过滤、倒序的 `[GameSummary]`；成功但零项返回空数组 | async、可取消；任一类别或分页失败则整体失败；取消不转为用户错误 | ViewModel → GameCatalog | 两个类别请求、任一失败原子失败、分页、去重、排序、空集合、取消 |
| IF-002 `makeReleaseDateWindow` | `now`、本地 `Calendar` / `TimeZone` | `[startInclusive, endExclusive)` UTC 绝对时刻及保守 API 日期包络 | 纯函数、无副作用 | GameCatalog → ReleaseDateWindow | 固定时钟；第 7/15 日含边界、午夜、UTC/本地跨日、DST |
| IF-003 `fetchCategoryPage` | 允许的类别、API 日期包络、page、`per=100` | 页面 DTO 与可用于终止判断的元数据 | async、可取消；HTTP/解码/契约错误分类返回；页内不并行 | GameCatalog → GameAPIClient | 只发两个允许类别；请求参数、页序、错误映射 |
| IF-004 `fetchDetail` | 已验证列表项 `id` | 对应 `GameDetail` | async、可取消；404 与其他错误区分；响应 ID 必须匹配 | Detail ViewModel / Catalog → GameAPIClient | 成功映射、null 字段、404、ID 不匹配、取消 |
| IF-005 `refreshOnColdLaunch` | App 完全启动事件；启动标识 | 驱动列表状态状态机 | 启动单飞；重复事件不重复请求；后台回前台不调用；新请求取消旧任务并隔离过期结果 | App lifecycle coordinator → GameListViewModel | 冷启动一次刷新、重复启动保护、前后台转换不刷新、取消竞态 |
| IF-006 `selectGame` | 列表中的 `GameSummary` | 以其 `id` 展示详情页 | 不创建外部 URL 动作；离开详情可取消读取 | GameListView → Navigation / Detail ViewModel | 行点击进入匹配 ID 详情；无商店跳转 |
| IF-007 `publishListState` | 加载结果或错误分类 | `loading` / `loaded` / `empty` / `failed` | 主线程/SwiftUI 隔离策略待版本决策；每个请求只提交一次最终态；陈旧任务无权提交 | GameListViewModel → GameListView | 每种状态可见文本精确性；失败/空状态仅有规定文案 |

## 网络契约约束

- `GET /api/v1/new`：分别传 `category=GAME_PUZZLE`、`category=GAME_CASUAL`；使用 `since`、`until`、`page`、`per`；`per` 不大于已验证上限 100；排序采用 API 默认 `released` 从新到旧，并由客户端再执行确定性排序。
- `GET /api/v1/app`：只传列表所选项目的 `id`。虽然 API 返回 `url`，接口不把 URL 暴露为外部导航能力。
- 认证头由经过用户批准的凭据边界注入；接口层不接受页面或视图传入 API Key，也不输出认证值。
- 以上网络请求均需验证成功 HTTP 状态、响应结构与字段契约；响应不得部分成功地伪装成完整列表。

## UI 状态可见合同

| 内部状态 | 列表页可见内容 |
|---|---|
| `loading` | 加载指示状态 |
| `loaded(nonEmpty)` | 目标游戏列表 |
| `empty` | 只显示 `No games found` |
| `failed` | 只显示 `Unable to load games` |

加载指示的具体视觉实现可用系统 SwiftUI 组件，不显示额外说明文本。详情页状态的用户可见错误合同仍待决；批准前不得擅定。
