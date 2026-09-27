# oh-my-posh 主题库

本目录是 [JanDeDobbeleer/oh-my-posh](https://github.com/JanDeDobbeleer/oh-my-posh) 官方主题库的镜像，
供 Script Studio 的交互式终端选择使用。

- 来源：`https://github.com/JanDeDobbeleer/oh-my-posh/tree/main/themes`
- 同步的上游修订：`03d192436d9550eabc5b48a8c08f1a5b441da410`（2026-09-26）
- 文件数：123 个 `.omp.json` + 2 个 `.omp.yaml` + `schema.json`

## 更新方式

```bash
cd /tmp && rm -rf omp-themes
git clone --depth 1 --filter=blob:none --sparse https://github.com/JanDeDobbeleer/oh-my-posh.git omp-themes
cd omp-themes && git sparse-checkout set themes
cp themes/*.omp.json themes/*.omp.yaml themes/schema.json <项目>/themes/
cd <项目> && git add themes && git commit -m "chore: sync oh-my-posh themes"
```

## 命名

主题名即去掉扩展名的文件名，例如 `blue-owl.omp.json` 的主题名是 `blue-owl`。
Script Studio 通过 `GET /api/themes` 列出它们，并把选中的主题传给交互式终端的
`oh-my-posh init --config`。

## 许可

主题文件版权归 oh-my-posh 项目所有（MIT）。
