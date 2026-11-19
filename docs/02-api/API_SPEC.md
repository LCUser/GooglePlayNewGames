# API 接口规格

- 文档编号：API-DOC-001
- 状态：阶段 2 验证中
- 数据源候选：playapi.info Free 套餐
- 官方文档：https://playapi.info/zh/api-docs.php

本文件在 API 验证完成前不得将文档描述直接视为已验证能力。

| API ID | 接口 | 用途 | 参数 | 返回字段 | 验证状态 |
|---|---|---|---|---|---|
| API-001 | `GET /api/v1/health` | 检查服务可用性 | 无 | `ok`、`status`、`time` | 已验证 |
| API-002 | `GET /api/v1/new` | 获取按首次发布日期筛选的新应用列表 | `days`、`category`、`limit`、`offset` | 待实测 | 待验证 |
| API-003 | `GET /api/v1/app` | 按应用 ID 获取游戏详情 | `id` | 待实测 | 待验证 |
| API-004 | `GET /api/v1/categories` | 获取类别列表，确认游戏类别取值 | 无 | 待实测 | 待验证 |
| API-005 | `GET /api/v1/search` | 评估日期区间和游戏类别查询的备选能力 | `q`、`category`、`released_after`、`released_before`、`limit`、`offset` | 待实测 | 待验证 |

## 认证
- 官方文档要求受保护接口通过 `X-API-Key` 请求头或 `Authorization: Bearer` 传递 API 密钥。
- 实测确认：`GET /api/v1/new` 缺少密钥时返回 HTTP 401、错误码 `missing_api_key`。
- API 密钥不得写入仓库、文档、测试证据或日志。
