# Gehao Dong：主动备选方案开发计划

从开始开发起按四周推进。Gehao Dong 负责 BackupAgent、替代方案搜索/刷新、Plan B/C 和备选 UI；基础应用沿用 `travel-planner/` 的 Jac + SQLite 结构。

## 每周交付

| 周次 | 工作内容 | 验收标准 |
| --- | --- | --- |
| 第 1 周：可运行的备选预览 | 定义本模块 draft 接口；实现合成库存 search/refresh；为雨天活动、延迟晚餐生成 Plan B/C；接入 Itinerary 页面；补充单元、服务测试及独立演示 | 演示能运行；来源、检查时间、有效期、触发条件可见；未知/不可用库存不进入候选；失败有明确提示；生成与刷新不改变原行程及预算 |
| 第 2 周：完整验证 | 对接 Person 2 的 RiskFlag，对接 Person 1 的 profile、ConstraintValidator 与预算结果；验证替换后的完整行程，加入时区、开放时间、交通缓冲、固定节点及硬约束 | 饮食、宠物、儿童、无障碍、预算或时间边界不通过的候选不能标为 valid；缺少证据保持 unknown；无解时给出原因 |
| 第 3 周：刷新与跨模块交接 | 保存备选及证据版本；模拟涨价、售罄、过期和 provider 失败；刷新后重新验证；输出给 Person 5 比较及 Person 4 重规划 | 旧证据不能直接用于选择；变更价格会重新验证；过期快照被拦截；不重复计算原支付金额；仍由 Person 4 应用修改、Person 5 获取旅客确认 |
| 第 4 周：集成与交付 | 完成“风险 → 备选 → 刷新 → 比较 → 旅客审阅”的联调；覆盖跨日、时区、并发更新、无备选、拒绝与重试；整理演示、接口和验证记录 | 两个端到端场景可复现；拒绝不改行程；确认后只更新模拟状态；桌面/窄屏可用；记录尚未支持的边界 |

周次是开发安排，不代表其他成员的模块已经完成。若共享接口尚不可用，使用明确标记的 fixture，并保持 `needs_validation`，不能把 mock 筛选称为完整行程验证。

## UI 分工

各负责人在 Roam 应用内设计和实现自己功能的 UI，复用现有导航、trip 上下文、配色和通用控件。需要时可以新增面板或页面，并与 Person 5 协调共享导航和页面结构。Gehao Dong 负责备选条件、Plan B/C 卡片、来源与有效期、刷新、空状态和错误提示；第一周已通过 `backup/frontend.jac` 接入现有 Itinerary。

## 第一周已实现

- `backup/models.jac`：`BackupCandidate`、`BackupOption`、`BackupPreview`，版本 `person3.backup-preview.v1`（保留已有机器接口标识；负责人已改为 Gehao Dong）。
- `tools/alternatives/mock.jac`：Boston 合成库存；按目的地/类别搜索、按 ID 刷新。USD 整数分，合成证据有效期 15 分钟。
- `backup/planner.jac`：确定性的 BackupAgent 雏形，最多两个草案，关联原 item、触发条件及行程快照指纹。Plan B/C 按 fixture 顺序命名，不表示推荐排名。
- `server/main.jac::preview_backups`：在同一 SQLite 读事务中取 trip/items；校验 item 属于当前 trip；不保存、预订或应用候选。
- `backup/frontend.jac`：Itinerary 中的独立备选面板，含空状态、错误状态、刷新、估价、来源、时间和排除原因。切换行程或刷新行程后清除旧预览。
- `backup/demo.jac`：无需服务、数据库或模型密钥的两个场景演示。
- `backup/test_planner.jac` 和 `server/test_backup.jac`：库存、证据、输入边界、序列化、跨 trip 隔离和不修改行程的验证。

## 接口与职责边界

请求：`preview_backups(trip_id, item_id, trigger)`；`trigger` 为 `rain`（activity）或 `arrival_delay`（food）。要求 item 有日期且未完成。场景由旅客手动选择，第一周没有自动风险检测。

响应含 `contract_version`、`mode="mock"`、`trip_id`、`item_id`、`base_snapshot`、`trigger`、`status`、`message`、`options`、`exclusions`。候选含原 item ID、激活条件、估价、来源、UTC 检查/失效时间及未完成校验列表。

- `status` 只有 `needs_validation` / `no_candidates`；第一周不会输出 `valid`。缺失/错误 item、错误场景、未定日期及已完成 item 会返回错误。
- `base_snapshot` 是整个 trip/items 的内容指纹，便于后续对接；不是 Person 4 的 graph version，也不能用于直接应用 patch。
- 库存是虚构的，`mock://boston-v1/...` 是 fixture 标识。时间表示本次模拟读取；独立演示使用固定时钟。刷新只会重读相同 fixture，涨价/售罄模拟在第 3 周接入。
- 仅支持 `Boston`、`Boston, MA`、`Boston, USA`（忽略大小写和首尾空白）；其他地点明确返回空。USD 之外不做兑换。
- 金额只是候选合成估价，不表示真实多人报价、立即支付额、退款损失或全程总价。Person 1/2/5 负责对应的权威计算与比较。
- 当前 trip/item 没有完整 traveler profile、结束时间、时区、依赖图及退款证据。日期、当地时间可行性、营业时段、人数计价、退款、交通和硬约束均待第 2 周完整校验。不会把未检查的要求默认为符合。
- 第一周不保存备选，也没有 accept/apply 按钮。后续共享 `AlternativePlan` 与 validator 接口需与其他 owner 协调；本次没有更改共享 schema 或实现其他成员模块。

## 运行演示与测试

在仓库的 `travel-planner/` 目录，使用可运行的 Jac 环境：

```sh
# 不写数据库，输出两个场景的 JSON
jac run backup/demo.jac

# 单元、端点与原有功能回归
jac test backup/test_planner.jac
jac test server/test_backup.jac
jac test server/main.test.jac
jac check --nowarn
jac build travel --as client

# 浏览器演示
jac run --dev travel
```

浏览器步骤：

1. 新建目的地为 `Boston`、币种为 `USD` 的 trip。
2. 添加有日期、未完成的 activity，例如 “Outdoor walk”；再添加有日期的 food，例如 “Dinner”。
3. 在 Itinerary 的备选面板选择雨天场景和 activity，点击 **Prepare Plan B / C**，检查两张卡片及排除原因。
4. 切换延迟到达场景和 Dinner，再生成两张卡片。点击 **Refresh mock ideas** 重新读取合成证据。
5. 检查原行程条目数、预算和 planned cost 不变。把目的地改为 Kyoto 后重试，会明确显示没有匹配的 mock 库存。

## 环境验证边界

2026-10-06 本机验收记录：

- 备选单元测试 8 项、服务集成测试 1 项、原有服务回归 3 项，全部通过。集成测试比较 SQLite 完整导出，确认生成成功及错误请求都没有改变存储内容。
- `jac check --nowarn` 检查 web/server/CLI 三个入口通过；客户端 production bundle 构建通过；独立 demo 成功输出两个场景。
- 浏览器通过真实 HTTP 服务验证雨天与延迟晚餐、刷新、切换场景清空旧结果；2 个原始条目和 USD 30 planned cost 保持不变；未捕获浏览器 console error。
- 浏览器使用单独的临时 SQLite 数据库，合成条目通过服务 API 准备。未验证真实预订、真实库存、全程可行性或原生移动端。

仓库 `jac.toml` 原有 pin 为 `0.37.23`。本机可用的 bundled launcher 为 `0.37.21`；第一周验证记录针对该本机版本，不代表已验证 `0.37.23`。保留仓库 pin，团队应在统一的 `0.37.23` 环境复跑上述命令。

本机 0.37.21 下原有 `cli add` 命令还触发 `save_item() missing ... item_id` 的默认参数兼容错误；没有把该原有问题纳入本次 Gehao Dong 功能改动。备选独立 demo 和浏览器备选流程已单独验证。

若出现 `failed to get the Python codec of the filesystem encoding`，这是本机 launcher 解压缓存问题。代码检查/无数据库演示可用一个新的临时 `TMPDIR` 让 launcher 重新解压。服务测试需要可用的 Jac Postgres runtime；已有本地实例时使用正常临时目录，避免改变 Unix socket 路径。
