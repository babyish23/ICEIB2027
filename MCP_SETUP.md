# TrailGuard TW 論文 MCP 設定

此設定會完成：

1. 檢查或安裝 Git、uv/uvx 與 Claude Code。
2. Clone 指定的 Overleaf Git 專案到
   `%USERPROFILE%\overleaf-projects\trailguard-tw-paper`。
3. 將 `trailguard_ieee.tex` 複製至 Overleaf 專案。
4. 以 `--repository` 限制 Git MCP 只能存取該論文 repository。
5. 將 MCP 以使用者範圍註冊為 `overleaf-trailguard-tw-paper`。

## 執行

在目前資料夾開啟 PowerShell：

```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
.\setup_overleaf_mcp.ps1
```

或直接提供參數：

```powershell
.\setup_overleaf_mcp.ps1 `
  -GitUrl "https://git.overleaf.com/YOUR_PROJECT_ID" `
  -FolderName "trailguard-tw-paper" `
  -McpName "overleaf-trailguard-tw-paper"
```

## Overleaf 認證

- Git 網址請從 Overleaf 專案的 Git integration 頁面取得。
- Git Credential Manager 要求密碼時，請使用 Overleaf 的 Git
  Authentication Token，不要使用一般登入密碼。
- Clone 完成後，在 Overleaf 將 `trailguard_ieee.tex` 設為 Main document。

## 驗證

```powershell
claude --version
uvx --version
claude mcp get overleaf-trailguard-tw-paper
git -C "$env:USERPROFILE\overleaf-projects\trailguard-tw-paper" status
```

第一次執行 `claude` 時會要求登入。Claude Code 需要支援的付費方案、
Claude Console 帳戶，或受支援的雲端供應商權限。
