# 锐捷交换机配置备份工具

自动批量备份锐捷（Ruijie）交换机运行配置的工具。

## 功能特性

- 批量备份多台锐捷交换机配置
- 自动通过SSH连接设备
- 自动进入特权模式（Enable）
- 过滤命令输出，只保留配置内容
- 自动打包为ZIP压缩文件
- 生成备份报告

## 文件说明

| 文件 | 说明 |
|------|------|
| AMconfigbak.ps1 | 主备份脚本 |
| plink.exe | PuTTY Link SSH客户端 |
| AM IP list1.txt | 交换机IP地址列表 |

## 使用方法

### 1. 配置IP地址列表

编辑 `AM IP list1.txt`，每行一个IP地址：

```
192.168.1.1
192.168.1.2
192.168.1.3
```

### 2. 配置脚本参数

编辑 `AMconfigbak.ps1`，修改以下配置：

```powershell
# 登录凭证
$Username = "admin"          # SSH用户名
$LoginPassword = "password"  # SSH登录密码
$EnablePassword = "enable"   # 特权模式密码

# 文件路径（建议使用绝对路径）
$PlinkPath = "C:\path\to\plink.exe"
$SwitchListFile = "C:\path\to\AM IP list1.txt"

# 备份保存目录
$BackupDir = "C:\Backup\SwitchConfigs"
```

### 3. 运行脚本

```powershell
powershell -ExecutionPolicy Bypass -File AMconfigbak.ps1
```

## 输出结果

脚本运行后会生成：
- `Switch_192.168.1.1_YYYYMMDD_HHmmss.txt` - 各交换机配置文件
- `SwitchConfigs_YYYYMMDD_HHmmss.zip` - 打包的压缩文件
- `BackupReport_YYYYMMDD_HHmmss.txt` - 备份报告

## 注意事项

1. **SSH密钥**：首次运行会提示确认SSH主机密钥，输入 `y` 确认
2. **网络要求**：确保能正常访问交换机的22端口（SSH）
3. **权限**：确保有交换机设备的登录权限
4. **路径**：建议使用绝对路径，避免路径问题

## 环境要求

- Windows系统
- PowerShell 5.0+
- 无需额外安装，plink.exe 已包含

## 许可协议

MIT License
