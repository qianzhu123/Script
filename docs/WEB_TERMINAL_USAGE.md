# Daily Web Terminal 使用说明

## 已完成能力

- 浏览器内 Web 终端，优先使用 `node-pty`，失败时回退到 `spawn` 兼容模式。
- 脚本分类卡片展示。
- 中间栏支持全局搜索脚本名称、说明、路径和分组；搜索时自动进入“全部脚本”，高亮并定位匹配项。
- 搜索结果支持 `Enter` 跳到下一个、`Shift+Enter` 跳到上一个、`Esc` 清空。
- 点击脚本后在 Web 终端中运行。
- 支持交互输入：`set /p`、菜单、`Y/N`、`pause`。
- 从网页运行脚本时隐藏额外的 Windows 终端窗口，输入和输出统一在浏览器终端完成。
- 支持多终端 Tab。
- 支持新建空终端。
- 支持结束、清屏、适配终端尺寸。
- 添加脚本弹窗：可从候选脚本选择，或粘贴脚本内容创建。
- 运行日志保存到 `D:\code\myweb\daily\logs`。
- 运行历史保存到 `D:\code\myweb\daily\logs\history.json`。

## 启动

```bat
cd /d D:\code\myweb\daily
npm install
npm start
```

或双击：

```text
D:\code\myweb\daily\start.bat
```

访问：

```text
http://127.0.0.1:3100
```

## node-pty 说明

真正的 Web 终端依赖 `node-pty`。如果 `npm install` 编译失败，需要安装：

- Node.js LTS
- Visual Studio Build Tools
- Python
- Windows SDK

项目已做兼容：即使 `node-pty` 未安装成功，页面仍会进入兼容模式，但兼容模式不是完整 PTY，交互体验不如 node-pty。

## UI 风格

当前界面参考：

- Linear：卡片、空间感、细腻阴影
- Raycast：脚本启动器体验
- Vercel Dashboard：开发者工具感
- Warp Terminal：终端 Dock 和多 Tab
- Semi/Arco Design：清新工作台布局

## 注意

当前项目仍只监听 `127.0.0.1:3100`，默认仅本机可访问。
不要改成 `0.0.0.0`，除非你后续添加登录和 token。

直接在资源管理器中双击 BAT、PS1 或快捷方式不属于网页运行流程，仍可能按脚本自身设置打开 Windows 终端。
