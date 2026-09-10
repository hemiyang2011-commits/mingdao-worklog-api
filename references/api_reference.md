# 明道云「工作表 API」参考（思凡数字核算系统 · 工作日志）

> 依据应用 API 开发文档（`https://www.mingdao.com/worksheetapi/2e045d26-06e8-4eb3-849c-f703a781f673`）
> 及官方帮助中心整理，并**实测验证**。字段 ID / rowid 均对应「思凡数字核算系统」生产环境。

## 1. 鉴权（已实测验证 ✅）

明道云「应用授权」的 `AppKey` + `SecretKey` 里，**`SecretKey` 就是预生成的静态签名（Sign）**，
调用接口时**直接原样当 `sign` 用**，不需要任何计算：

```
请求体：{ "appKey": "<AppKey>", "sign": "<SecretKey 原样>", "worksheetId": "...", ... }
```

- ❌ 不需要 `AppKey=...&SecretKey=...&Timestamp=...` 做 SHA256 + base64 那套（那是「组织密钥」的算法，两者不同）。
- ❌ 不需要传时间戳。
- ✅ 实测：`sign = SecretKey 值` 直接调用，`getWorksheetInfo` / `addRow` 均返回成功。

> 组织密钥（组织管理 → 其他 → 组织密钥）才是时间戳签名：
> `sign = BASE64(HEX(SHA256("AppKey=ak&SecretKey=sk&Timestamp=毫秒")))`，且时间戳要随请求传递。
> 本 skill 用的是「应用授权」密钥，sign 就是 SecretKey 值本身。

## 2. 新增行记录（核心接口）

```
POST https://api.mingdao.com/v2/open/worksheet/addRow
Content-Type: application/json
```

请求体：
```json
{
  "appKey": "<AppKey>",
  "sign": "<SecretKey 原样>",
  "worksheetId": "<工作表ID>",
  "controls": [
    { "controlId": "<字段ID>", "value": "<值>" }
  ],
  "triggerWorkflow": true
}
```

响应：
```json
{ "data": "<新记录 rowid>", "success": true }
```

### 错误对照表

| error_code | 说明 |
|---|---|
| 1 | 成功 |
| 0 | 失败 |
| 10001 | 缺少参数 / Http Headers verification failed（sign 传错时常见） |
| 10002 | 参数值错误 |
| 10005 | 数据操作无权限（授权没勾该表/该权限） |
| 10007 | 数据不存在 |
| 10101 | 请求令牌不存在 |
| 99999 | 数据操作异常 |

## 3. 其它接口

| 用途 | URL | 方法 |
|---|---|---|
| 获取工作表结构 | `/v2/open/worksheet/getWorksheetInfo` | POST |
| 分页获取记录 | `/v2/open/worksheet/getFilterRows` | POST |
| 批量新增 | `/v2/open/worksheet/addRows` | POST |
| 更新行 | `/v2/open/worksheet/editRow` | POST |
| 删除行 | `/v2/open/worksheet/deleteRow` | POST |

> 注：明道云还有新一代 v3 应用 API（`POST /v3/app/worksheets/{id}/rows`，请求头 `HAP-Appkey` / `HAP-Sign`，
> sign 同样是 SecretKey 原样）。本 skill 默认走 v2，文档最全、已验证。

### ⭐ getFilterRows 必须带 viewId（授权按「视图」粒度，实测）

明道云「应用授权」里，数据读取权限是**按视图（view）**授予的，不是按整表：

- `getFilterRows` **不带 `viewId` → 10005 数据操作无权限**（即使表本身有读权限）。
- 必须带上**被授权了的那个视图**的 `viewId`，才能读到数据。
- 不同视图可能返回不同的字段 key（别名 vs controlId），取值时要按实际返回为准。

已实测确认的本环境「可读视图」及对应字段 key：

| 表 | 可读视图 | viewId | 名称字段 key（读取时用） |
|---|---|---|---|
| 工作日志 | 全部 | `69a64ee46718b093003496b7` | `gznr`(内容)/`ygxm`(员工名)/`xmmc`(项目名)/`riqi`(日期)/`gongshi`(工时)/`shiduan`(时段) |
| 项目档案 | 项目 | `6944e0d84a3e9b81f3584788` | `65e57b98af2cbab9cc8bb162`（=controlId） |
| 员工档案 | 员工通讯录 / 员工信息 | `696db4933528addfe1f75dbf` / `698549a97104409881021a62` | `employeeName`（**别名**，非 controlId） |

> 其它视图（如「全部」「项目管理」「员工花明册」等）未授权，读会 10005。

## 4. 工作日志表字段对照（worksheetId `699fc3c07269639034797d29`）

| 字段 | controlId | 类型 | value 写法（实测） |
|---|---|---|---|
| 日期 | `699fc3c07269639034797d2f` | Date | `"2026-09-04"` |
| 员工 | `69a64eb86718b0930034962d` | Relation（单条） | `"<员工rowid>"`（**字符串，非数组**） |
| 项目 | `69c49e8b37073b86f1917e45` | Relation（单条） | `"<项目rowid>"`（**字符串，非数组**） |
| 工作内容 | `699fc3c07269639034797d2d` | Text | `"开发2小时"` |
| 工时 | `699fc3c07269639034797d2e` | Number | `2` |
| 时段 | `6a9a2eaf810677a5e2f14626` | Dropdown（单选） | `"<时段key>"`（**字符串，非数组**） |

时段 key：

| 显示名 | key |
|---|---|
| 全天 | `624a039b-0e65-4585-a03d-4088b2dd2b7f` |
| 上午 | `4413d96e-aa0c-4032-81b8-b0742939de65` |
| 下午 | `4d818de0-67b4-4824-a529-359706ffefde` |
| 其它 | `0d99859c-e690-4518-a081-1718cfe1864e` |

## 5. 项目档案表（worksheetId `6796e72b863bad61f3a9e2fa`）

- 项目名 controlId：`65e57b98af2cbab9cc8bb162`（读取视图「项目」返回的 key 就是这个 controlId）。
- 可读视图「项目」viewId：`6944e0d84a3e9b81f3584788`（281 条）。
- 拉取后用 `scripts/match_project.py` 做模糊匹配得到项目 rowid。
- 示例：`中央厨房` → 全称「海南物管中央厨房供应链系统」→ rowid `3d95d78b-ec31-4d31-af8b-d689c6462875`。

## 5.1 员工档案表（worksheetId `69377f2a5326c71216b47b44`）

- 员工字段（controlId `69a64eb86718b0930034962d`）指向此表（dataSource）。
- 员工姓名 controlId：`69377f4b8b7b12fb56742613`；但可读视图返回的 key 是**别名 `employeeName`**（不是 controlId）。
- 可读视图「员工通讯录」viewId：`696db4933528addfe1f75dbf`（36 条）；「员工信息」`698549a97104409881021a62`（164 条）。
- 拉取后用 `scripts/match_project.py` 做「员工名 → rowid」模糊匹配。
- 示例：`何伟聪` → rowid `7bc879aa-59df-4beb-bb23-181cc4e9cfdf`。

## 6. 字段 value 通用规则（各类型，实测）

| 类型 | value 写法 |
|---|---|
| 文本 Text | 字符串 |
| 数字/金额 Number | 数字或数字字符串 |
| 日期 Date | `"YYYY-MM-DD"` |
| 日期时间 DateTime | `"YYYY-MM-DD HH:mm:ss"` |
| 单选 Dropdown | `"<选项key>"`（**字符串**） |
| 多选 MultipleSelect | `["<key1>", "<key2>"]`（数组） |
| 关联 Relation（单条） | `"<rowid>"`（**字符串**） |
| 关联 Relation（多条） | `["<rowid1>", "<rowid2>"]`（数组） |
| 成员 Collaborator | `["<accountId>"]` |
| 系统字段 `ownerid` | `"<HAP accountId>"`（**字符串**，不是数组） |
| 系统字段 `caid` | 不能直接写，但**写入 ownerid 时会自动同步**；未传 ownerid 时 = `user-api` |
| 系统字段 `uaid` | 不能写，addRow 后被工作流触发则 = `user-workflow` |
| 附件 Attachment | 见官方文档（URL 或 base64） |
| 公式/自增编号/拼接 | 不要传，系统自动算 |

## 7. 踩坑记录（实测）

- **sign 直接 = SecretKey 值**，不要再做 SHA256+base64。做了反而 401「Http Headers verification failed」。
- `controls` 必须是数组，元素键名是 `controlId`（不是 `id`、不是 `fieldId`）。
- 单条关联字段写 **rowid 字符串**（不是数组，传数组会 JSON 解析报错）。
- 单条下拉字段写 **key 字符串**（不是数组，不是显示文本）。
- **`getFilterRows` 必须带 `viewId`**（授权按视图粒度），且要带**被授权**的那个视图；否则 10005。
- 读取时字段 key 可能是**别名**（如员工表 `employeeName`）而非 controlId，取值要按实际返回的 key，不要硬套 controlId。
- 写入 addRow 用的字段键名仍是 `controlId`（与读取返回的 key 无关），不要混淆。
- **写入 ownerid**：`controls` 里加 `{"controlId": "ownerid", "value": "<HAP accountId 字符串>"}`，
  顶部 `ownerid` 字段名无效。
- **ownerid 与 caid 联动**：写入 ownerid 时，`caid`（创建人）会同步为同一个 accountId；
  未传 ownerid 时 `caid` = `user-api`。`uaid`（最后修改人）仍由系统控制，写入后可能被工作流改写。
