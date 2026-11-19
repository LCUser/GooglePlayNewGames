# API 接口规格

- 文档编号：API-DOC-001
- 状态：阶段 2 验证中
- 数据源候选：playapi.info Free 套餐
- 官方文档：https://playapi.info/zh/api-docs.php

本文件在 API 验证完成前不得将文档描述直接视为已验证能力。

| API ID | 接口 | 用途 | 参数 | 返回字段 | 验证状态 |
|---|---|---|---|---|---|
| API-001 | `GET /api/v1/health` | 检查服务可用性 | 无 | `ok`、`status`、`time` | 已验证 |
| API-002 | `GET /api/v1/new` | 按首次发布日期获取新应用 | `since`、`until`、`category`、`min_installs`、`lang`、`sort`、`order`、`page`、`per` | 列表项字段见数据字典 | 当前产品所需能力已验证 |
| API-003 | `GET /api/v1/app` | 按应用 ID 获取详情 | `id` | 详情字段见数据字典 | 已验证 |
| API-004 | `GET /api/v1/categories` | 获取类别及 `game` 标记 | 无 | `total`、`categories[]` | 已验证 |
| API-005 | `GET /api/v1/availability` | 查询应用国家可用性数据 | `id` | `countries_count`、`worldwide`、`countries`、`note`、`source` | 已验证；部分应用不提供国家明细 |

## 认证
- 官方文档要求受保护接口通过 `X-API-Key` 请求头或 `Authorization: Bearer` 传递 API 密钥。
- 实测确认：`GET /api/v1/new` 缺少密钥时返回 HTTP 401、错误码 `missing_api_key`。
- API 密钥不得写入仓库、文档、测试证据或日志。

## 已验证行为与限制
- `/new` 的 `since`、`until` 日期范围可用；同日起止日期的样本查询返回该日记录。列表 `released` 为 UTC 时间戳，用户需求按设备本地日历日计算，仍需在阶段 3 明确日期换算规则。
- `/new` 默认按 `released` 从新到旧返回；`page`、`per` 可用，实测 `per=100` 返回 100 条。单个样本条件下 `order=asc` 与 `order=desc` 返回相同首条记录。
- 官方规格限制 `per` 为 1–100，单次查询最多可翻到第 10,000 条；`/new` 支持 `lang` 和 `sort`。通用排序规格包含 `order=asc|desc`，但本次 asc/desc 实测样本相同，未改变默认新到旧顺序。
- `category` 接受具体类别 ID。`category=GAME` 实测返回 0 条；产品仅使用 `GAME_PUZZLE` 与 `GAME_CASUAL` 两个类别，不得请求或展示其他游戏类别。
- 2026-11-04 至 2026-11-12 的历史查询中，目标两类分别返回 4,254 和 2,848 条记录。产品要求展示符合条件的列表，不要求单次全量下载全部记录。
- 产品不限定国家/地区。`/new` 未验证到可限定 US 的请求参数；官方说明的数据来源与 `/availability` 的样本限制仅作为 API 行为记录，不构成产品市场过滤要求。
- 跨时段数据更新与稳定性验证已按用户决定废弃，不属于产品需求或 Gate 2 验收范围。
