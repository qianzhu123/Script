# Daily Web Terminal 开发文档

> 目标：把现有 `D:\code\myweb\daily` 从“按钮式脚本控制台”升级为“本机 Web 终端 + 脚本管理平台”。
>
> 核心原则：尽量不破坏原 bat/ps1 使用习惯；网页端能像真实 CMD/PowerShell 一样交互输入、查看实时输出、处理 pause/set /p/菜单类脚本。

---

## 1. 背景与问题

当前项目已经能展示并调用脚本，但遇到以下典型问题：

1. **交互式 bat 不适合普通 exec/spawn 模式**
   - `set /p` 需要继续输入；
   - `pause` 会等待任意键；
   - 多级菜单脚本需要多轮输入；
   - 用 `stdinTemplate` 预置输入容易错位。

2. **Windows 编码复杂**
   - 很多 bat 使用 GBK/CP936；
   - Node/浏览器默认 UTF-8；
   - 直接管道输出会产生中文乱码。

3. **界面体验不足**
   - 普通列表难以管理大量脚本；
   - 日志输出与操作区分离；
   - 浏览器原生 confirm 弹窗风格差，且遮挡体验不好；
   - 不能像真实终端一样实时输入。

因此推荐升级为：

```text
Web UI
  ↓ WebSocket
Node.js 后端
  ↓ node-pty / winpty / conpty
真实 CMD / PowerShell / pwsh 伪终端
  ↓
项目内 bat / ps1 / lnk 脚本
```

---

## 2. 总体目标

### 2.1 第一目标

实现一个本机访问的 Web 终端系统：

- 页面点击脚本后，在右侧或底部打开真实终端会话；
- 终端支持实时输出；
- 用户可以在网页终端中继续输入；
- 支持 `set /p`、`pause`、菜单选择、长运行服务；
- 每次执行保存完整日志；
- 保留脚本白名单与风险确认；
- 原 bat/ps1 不必为了网页全部重写。

### 2.2 第二目标

增强脚本管理能力：

- 添加脚本；
- 编辑脚本元信息；
- 移动/复制脚本到项目目录；
- 分类、标签、收藏；
- 最近使用；
- 运行历史；
- 脚本详情预览；
- 参数表单与终端模式并存。

### 2.3 第三目标

打造更现代、更清新的 UI：

- 不再采用单色后台管理风；
- 使用卡片、玻璃拟态、柔和渐变、分区色彩；
- 参考大厂设计系统，但不照搬；
- 左侧脚本工作台 + 中央卡片/详情 + 右侧/底部终端。

---

## 3. 推荐技术栈

## 3.1 后端

### 推荐方案

```text
Node.js + Express + ws/socket.io + node-pty
```

依赖建议：

```json
{
  "express": "^4.x",
  "ws": "^8.x",
  "node-pty": "^1.x",
  "iconv-lite": "^0.6.x",
  "chokidar": "^3.x",
  "nanoid": "^5.x"
}
```

说明：

- `express`：提供 API 与静态资源；
- `ws` 或 `socket.io`：浏览器与后端终端会话通信；
- `node-pty`：创建真实伪终端，解决交互式 bat 的根本问题；
- `iconv-lite`：必要时处理 GBK/UTF-8；
- `chokidar`：监听 `bat/ps1/config` 文件变化；
- `nanoid`：生成会话 ID、脚本 ID、日志 ID。

### node-pty 风险与注意事项

Windows 下 `node-pty` 需要本机编译环境或匹配的预编译包。可能需要：

- Node.js LTS；
- Visual Studio Build Tools；
- Python；
- Windows SDK。

如果安装困难，可提供 fallback：

1. 优先使用 `node-pty`；
2. 失败时退回当前 `spawn + runner.cmd`；
3. 对复杂脚本提示“建议在新终端打开”。

---

## 3.2 前端

### 轻量方案

```text
原生 HTML + CSS + JS + xterm.js
```

适合当前项目继续迭代，改动小。

### 推荐升级方案

```text
Vite + React + TypeScript + xterm.js + Zustand + Tailwind CSS
```

优点：

- 组件化；
- 后续功能多时更好维护；
- UI 主题更容易做；
- 状态管理清晰；
- 终端组件、脚本卡片、弹窗、抽屉都可独立维护。

### UI 组件库可选

如果采用 React：

- Ant Design 5：企业级、稳定、文档好；
- Arco Design：字节跳动设计系统，更轻快，颜色更活；
- Semi Design：抖音/飞书系风格，现代、简洁；
- Mantine：现代、清新、主题能力强；
- NextUI / HeroUI：卡片感、现代感强，适合漂亮面板；
- shadcn/ui：高级感强，但偏 Tailwind/设计师风，需要自行组合。

---

## 4. 系统架构

```text
D:\code\myweb\daily
├─ server.js / server/
│  ├─ api scripts
│  ├─ websocket terminal
│  ├─ pty session manager
│  ├─ logs manager
│  └─ config manager
├─ public/ 或 frontend/
│  ├─ dashboard
│  ├─ terminal panel
│  ├─ script detail drawer
│  ├─ add/edit script modal
│  └─ settings
├─ bat/
│  └─ *.bat / *.cmd / *.lnk
├─ ps1/
│  └─ *.ps1
├─ config/
│  ├─ scripts.json
│  ├─ categories.json
│  └─ settings.json
├─ logs/
│  ├─ terminal/
│  └─ runs/
└─ docs/
```

---

## 5. 核心模块设计

## 5.1 脚本配置模型

建议升级 `config/scripts.json` 单项结构：

```json
{
  "id": "kill-port",
  "name": "KillPort.bat",
  "displayName": "端口占用查杀",
  "path": "D:\\code\\myweb\\daily\\bat\\KillPort.bat",
  "type": "bat",
  "shell": "cmd",
  "category": "端口与服务",
  "tags": ["端口", "进程", "网络"],
  "description": "查询端口占用，并可选择终止进程。",
  "risk": "high",
  "favorite": true,
  "runMode": "terminal",
  "workingDirectory": "D:\\code\\myweb\\daily\\bat",
  "encoding": "gbk",
  "requiresConfirm": true,
  "argsTemplate": ["{port}"],
  "inputs": [
    {
      "name": "port",
      "label": "端口号",
      "type": "number",
      "required": true,
      "placeholder": "8080"
    }
  ],
  "terminal": {
    "initialCommand": "call \"{path}\" {args}",
    "autoFocus": true,
    "keepAlive": true,
    "closeOnExit": false
  },
  "createdAt": "2026-06-08T00:00:00.000Z",
  "updatedAt": "2026-06-08T00:00:00.000Z"
}
```

### runMode 取值

```text
form       表单执行，适合无交互脚本
terminal   Web 终端执行，适合 set /p / pause / 菜单脚本
external   打开系统新终端，适合长期服务或需管理员权限脚本
link       打开 .lnk 快捷方式
```

---

## 5.2 Web 终端模块

### 后端职责

1. 创建 PTY 会话；
2. 接收前端输入；
3. 把终端输出实时发送给前端；
4. 记录日志；
5. 控制会话生命周期；
6. 支持窗口大小变化；
7. 支持中断、重启、关闭。

### WebSocket 消息协议

前端 -> 后端：

```json
{ "type": "terminal:create", "scriptId": "kill-port", "args": { "port": "8080" } }
```

```json
{ "type": "terminal:input", "sessionId": "xxx", "data": "Y\r" }
```

```json
{ "type": "terminal:resize", "sessionId": "xxx", "cols": 120, "rows": 32 }
```

```json
{ "type": "terminal:kill", "sessionId": "xxx" }
```

后端 -> 前端：

```json
{ "type": "terminal:created", "sessionId": "xxx" }
```

```json
{ "type": "terminal:data", "sessionId": "xxx", "data": "正在查询端口..." }
```

```json
{ "type": "terminal:exit", "sessionId": "xxx", "code": 0 }
```

```json
{ "type": "terminal:error", "message": "node-pty unavailable" }
```

---

## 5.3 终端启动策略

Windows 下建议默认启动：

```text
cmd.exe /k chcp 936 >nul & cd /d "脚本目录" & call "脚本路径" 参数...
```

对于 PowerShell：

```text
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "脚本路径" 参数...
```

对于 `.lnk`：

```text
cmd.exe /c start "" "快捷方式路径"
```

注意：

- Web 运行器创建 PowerShell、Python 和 CMD 子进程时必须使用 `windowsHide: true`，避免系统终端与浏览器终端重复显示；
- 子进程的 `stdin`、`stdout` 和 `stderr` 仍通过管道连接浏览器，隐藏窗口不能影响交互输入；
- 终端模式不必模拟 stdinTemplate；
- 用户可以直接在 xterm.js 里输入；
- `pause` 也可以正常响应；
- 菜单类脚本可以继续输入数字或 Y/N。

---

## 5.4 脚本添加功能

脚本列表顶部搜索框位于当前分组标题和“新增脚本”按钮之间，并保持单行布局。输入查询后必须切换到“全部脚本”，跨所有分组匹配名称、说明、路径和分组名称；匹配内容高亮，首项自动选中并滚动到可见区域。`Enter` 和 `Shift+Enter` 循环切换结果，`Esc` 清空搜索。搜索状态下禁止拖拽排序，避免对过滤列表写入错误顺序。

添加脚本弹窗/抽屉应支持：

### 添加方式

1. 从候选列表选择已有脚本；
2. 输入本地路径导入；
3. 粘贴脚本内容新建；
4. 扫描 `Desktop` 与 `D:\应用\脚本` 顶层脚本；
5. 后续支持拖拽脚本文件到页面。

### 基础信息

- 显示名称；
- 文件名；
- 类型：bat/cmd/ps1/lnk；
- 分类；
- 标签；
- 描述；
- 风险等级；
- 是否收藏；
- 是否需要确认；
- 运行模式：表单/终端/外部终端/快捷方式。

### 参数配置

- 参数字段名；
- 标签；
- 类型：text/number/path/url/select/boolean/password；
- 是否必填；
- 默认值；
- placeholder；
- select 选项；
- 参数模板；
- 工作目录；
- 环境变量。

### 保存动作

- 复制脚本到 `bat/` 或 `ps1/`；
- 避免同名覆盖，必要时追加后缀；
- 通过服务端保存配置前，先将当前 `config/scripts.json` 备份为 `backup/scripts-YYYY-MM-DD_HH-mm-ss-SSS.json`；
- 备份失败时取消配置写入；
- 更新 `config/scripts.json`；
- 记录创建时间；
- 刷新页面脚本列表。

服务启动时只清理文件名符合上述自动备份格式、且文件名时间戳已超过七天的文件。`backup/scripts.json` 及其他手工备份不参与自动清理。人工或 AI 直接修改配置前必须先执行 `npm run backup-config`。

---

## 5.5 日志与历史

每次运行生成一条历史记录：

```json
{
  "runId": "20260608-152313-kill-port",
  "scriptId": "kill-port",
  "scriptName": "KillPort.bat",
  "mode": "terminal",
  "startedAt": "2026-06-08T15:23:13.031Z",
  "endedAt": "2026-06-08T15:24:00.000Z",
  "exitCode": 0,
  "args": { "port": "8080" },
  "logPath": "D:\\code\\myweb\\daily\\logs\\terminal\\xxx.log"
}
```

页面功能：

- 最近运行；
- 按脚本查看历史；
- 打开日志；
- 下载日志；
- 复制输出；
- 清理旧日志。

---

## 5.6 安全设计

本项目是本机脚本控制台，风险高于普通网站。

必须保留：

1. 只监听 `127.0.0.1`；
2. 只执行白名单脚本；
3. 高风险脚本二次确认；
4. 禁止任意命令执行接口；
5. 路径限制在项目目录、桌面顶层、指定脚本目录；
6. 添加脚本时显示真实路径与风险提示；
7. 未来可增加本机 token。

可选增强：

- 首次启动生成 `config/settings.json` token；
- 页面访问需要 token；
- 运行高风险脚本需要输入确认词；
- 记录所有执行历史。

---

## 6. UI/UX 设计方案

## 6.1 布局建议

推荐使用“工作台”布局：

```text
┌────────────────────────────────────────────────────────────┐
│ 顶部栏：Daily Terminal / 状态 / 快捷操作 / 设置            │
├──────────────┬──────────────────────────────┬──────────────┤
│ 左侧导航      │ 中间脚本工作区                 │ 右侧详情面板   │
│ 分类          │ 卡片/表格/收藏/最近使用         │ 参数/说明/历史 │
│ 标签          │                              │              │
├──────────────┴──────────────────────────────┴──────────────┤
│ 底部或浮动：Web Terminal Tabs                               │
└────────────────────────────────────────────────────────────┘
```

### 推荐交互

- 点击脚本卡片：右侧显示详情；
- 点击“运行”：底部打开一个终端 Tab；
- 多个脚本可有多个终端 Tab；
- 高风险脚本弹出自定义居中 Modal；
- 添加脚本使用右侧 Drawer 或居中大 Modal；
- 历史日志在详情面板中展示。

---

## 6.2 视觉风格建议

不要做成单一深色/单一蓝色后台。推荐“清新多区域色彩”：

- 背景：非常浅的蓝灰或米白；
- 顶部：半透明玻璃质感；
- 分类：使用不同柔和色块；
- 脚本卡片：白色卡片 + 彩色角标；
- 高风险：珊瑚红/橙色；
- 低风险：薄荷绿；
- 终端：深色，但外围 UI 保持明亮；
- 终端 Tab：类似 VS Code / Warp 的标签体验。

---

## 7. UI 参考模板推荐

以下是适合参考的设计方向，不建议完全照搬。

## 7.1 Arco Design 风格

来源：字节跳动 Arco Design

适合原因：

- 明亮、现代；
- 后台系统能力强；
- 卡片、表格、弹窗、抽屉都成熟；
- 色彩比 Ant Design 更轻快。

适合本项目的部分：

- 左侧导航；
- Drawer 添加脚本；
- Modal 风险确认；
- Tag 标签；
- Card 脚本卡片。

关键词：

```text
Arco Design dashboard admin card drawer modal
```

---

## 7.2 Semi Design / 飞书风格

来源：字节/飞书生态

适合原因：

- 清爽；
- 留白好；
- 信息密度合适；
- 适合“工具工作台”。

适合本项目的部分：

- 顶部工作台；
- 最近使用；
- 脚本详情面板；
- 设置页面。

关键词：

```text
Semi Design admin dashboard workspace
```

---

## 7.3 Linear 风格

来源：Linear 产品设计

适合原因：

- 高级感强；
- 动效克制；
- 适合命令中心、任务流、快捷操作。

适合本项目的部分：

- 快捷命令面板；
- 运行历史；
- 任务状态；
- 脚本卡片 hover 效果。

关键词：

```text
Linear app dashboard command palette terminal
```

---

## 7.4 Vercel / Next.js Dashboard 风格

适合原因：

- 清新、技术感强；
- 适合开发者工具；
- 卡片、指标、部署记录等元素可借鉴。

适合本项目的部分：

- 脚本运行状态；
- 日志历史；
- 服务状态卡片；
- 顶部导航。

关键词：

```text
Vercel dashboard UI cards logs terminal
```

---

## 7.5 Raycast 风格

适合原因：

- 非常适合脚本/命令启动器；
- 快捷、键盘友好；
- 脚本搜索与分类体验好。

适合本项目的部分：

- 命令面板；
- 快速运行；
- 收藏命令；
- 最近运行。

关键词：

```text
Raycast command palette extension UI
```

---

## 7.6 Warp Terminal 风格

适合原因：

- 现代终端体验；
- 命令块输出清晰；
- 适合 Web Terminal 参考。

适合本项目的部分：

- 终端 Tab；
- 命令输出块；
- 复制输出；
- 运行状态。

关键词：

```text
Warp terminal UI tabs command blocks
```

---

## 7.7 推荐组合

最适合本项目的组合：

```text
整体工作台：Semi / Arco
脚本卡片：Vercel / Linear
命令面板：Raycast
终端体验：Warp / VS Code Terminal
弹窗抽屉：Arco / Ant Design 5
```

---

## 8. 页面功能规划

## 8.1 首页 Dashboard

展示：

- 常用脚本；
- 最近运行；
- 高风险脚本提醒；
- 正在运行的终端会话；
- 日志数量；
- 服务状态。

---

## 8.2 脚本库 Scripts

功能：

- 分类导航；
- 卡片视图/紧凑列表切换；
- 标签过滤；
- 收藏；
- 添加脚本；
- 编辑脚本；
- 删除配置但不删除文件；
- 打开所在目录；
- 查看脚本内容。

---

## 8.3 终端 Terminal

功能：

- 多 Tab；
- 实时输入输出；
- 支持复制、清空、下载日志；
- 支持 Ctrl+C；
- 支持关闭会话；
- 支持重启上一次命令；
- 支持调整字号；
- 支持主题切换。

---

## 8.4 添加脚本 Add Script

功能：

- 候选脚本列表；
- 选择已有脚本；
- 粘贴内容创建；
- 自动识别类型；
- 自动建议分类；
- 自动检测是否包含 `set /p`、`pause`、`choice`；
- 自动建议 runMode；
- 保存到项目目录；
- 写入配置。

---

## 8.5 历史 Logs

功能：

- 按时间查看；
- 按脚本筛选；
- 按状态筛选；
- 打开日志详情；
- 下载日志；
- 清理旧日志。

---

## 8.6 设置 Settings

功能：

- 默认 Shell：cmd / powershell / pwsh；
- 默认编码：GBK / UTF-8；
- 是否启用 token；
- 日志保留天数；
- 主题风格；
- 默认终端字号；
- 脚本扫描目录。

---

## 9. 开发阶段计划

## 阶段 0：备份与稳定当前项目

- 保存当前 `server.js/public/config`；
- 新建 `docs/` 文档；
- 不删除原 bat/ps1。

## 阶段 1：引入 WebSocket + xterm.js

目标：先跑通一个手动终端。

- 后端增加 `/ws/terminal`；
- 前端增加 xterm.js 页面；
- 创建 cmd.exe PTY；
- 支持输入输出；
- 支持 resize；
- 支持关闭。

## 阶段 2：脚本通过终端运行

目标：点击脚本后创建终端会话。

- 根据 scriptId 找配置；
- 拼接安全命令；
- 进入脚本工作目录；
- 执行 bat/ps1/lnk；
- 保存日志；
- 显示状态。

## 阶段 3：重做 UI 工作台

目标：形成现代脚本平台。

- 顶部栏；
- 左侧导航；
- 中间脚本卡片；
- 右侧详情；
- 底部终端 Tabs；
- 自定义 Modal 替代浏览器 confirm。

## 阶段 4：完善添加脚本

目标：真正可以从页面导入脚本。

- 候选列表；
- 复制脚本到项目；
- 选择分类；
- 编辑参数；
- 保存配置；
- 自动刷新。

## 阶段 5：历史、日志、设置

目标：增强可维护性。

- 历史记录；
- 日志详情；
- 配置设置；
- 清理日志；
- 收藏/最近运行。

## 阶段 6：质量与安全

目标：长期可用。

- token；
- 路径校验；
- 错误提示；
- node-pty fallback；
- README 更新。

---

## 10. 优先级建议

最高优先级：

1. Web 终端；
2. xterm.js；
3. 自定义弹窗；
4. 终端运行脚本；
5. 添加脚本功能。

中优先级：

1. 日志历史；
2. 脚本编辑；
3. 分类/标签/收藏；
4. 设置页面。

低优先级：

1. 命令面板；
2. 拖拽导入；
3. 主题市场；
4. 统计图表。

---

## 11. 推荐最终界面方向

建议项目命名：

```text
Daily Terminal Workspace
```

视觉关键词：

```text
清新、轻量、开发者工具、命令工作台、柔和渐变、白色卡片、深色终端、彩色分类
```

推荐首页结构：

```text
顶部：项目名 / 运行状态 / 添加脚本 / 设置
左侧：全部、收藏、最近、端口与服务、安卓逆向、开发工具、文件处理、磁盘清理、系统维护、快捷方式
中间：脚本卡片网格，每张卡片有图标、说明、风险、运行按钮
右侧：当前脚本详情、参数、历史
底部：可收起 Web Terminal，多 Tab
```

---

## 12. 对现有问题的解决关系

| 当前问题 | Web 终端方案解决方式 |
|---|---|
| set /p 需要输入 | xterm.js 输入直接进入真实终端 |
| pause 卡住 | 用户可在网页终端按任意键 |
| 多级菜单 | 用户可继续输入菜单编号 |
| Y/N 确认错位 | 不再依赖 stdinTemplate |
| 输出区域不方便 | 终端固定在底部或独立 Tab |
| 浏览器 confirm 难看 | 使用自定义 Modal |
| 中文乱码 | 终端启动时设置 chcp 936，必要时配置编码 |
| 长运行脚本 | 终端会话可持续存在，可手动关闭 |

---

## 13. 下一步实施建议

建议下一步直接进入“阶段 1”：

1. 安装依赖：

```bash
npm install ws xterm xterm-addon-fit node-pty nanoid chokidar
```

2. 后端新增终端 WebSocket；
3. 前端引入 xterm.js；
4. 先做一个“打开 CMD 终端”按钮；
5. 确认能输入 `dir`、`chcp`、`pause`；
6. 再接入脚本运行。

如果 `node-pty` 安装失败，则先记录错误，改为 fallback 方案。
