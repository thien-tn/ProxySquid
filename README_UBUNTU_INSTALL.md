# Hướng dẫn cài đặt Squid Proxy Manager trên Ubuntu

## Yêu cầu hệ thống
- Ubuntu 18.04 LTS hoặc mới hơn
- Quyền root (sudo)
- Kết nối internet ổn định
- Ít nhất 2GB dung lượng trống

## Cài đặt cơ bản

### Bước 1: Tải và chuẩn bị
```bash
# Tải về và giải nén project
git clone <repository_url>
cd ProxySquid

# Cấp quyền thực thi
chmod +x install.sh
chmod +x test_install.sh
chmod +x scripts/*.sh
chmod +x lib/*.sh
```

### Bước 2: Kiểm tra hệ thống trước khi cài đặt
```bash
# Chạy script test
sudo ./test_install.sh
```

### Bước 3: Cài đặt Squid
```bash
# Chạy cài đặt chính
sudo ./install.sh
# Chọn option 1: Cài đặt Squid Proxy
```

## Xử lý lỗi phổ biến

### Lỗi APT lock
Nếu gặp lỗi "dpkg lock" hoặc "apt lock":
```bash
# Dừng tất cả processes APT
sudo pkill -f apt
sudo pkill -f dpkg

# Xóa lock files
sudo rm /var/lib/dpkg/lock*
sudo rm /var/cache/apt/archives/lock

# Configure dpkg
sudo dpkg --configure -a

# Update lại
sudo apt update
```

### Lỗi kết nối repositories
```bash
# Kiểm tra DNS
nslookup archive.ubuntu.com

# Reset network
sudo systemctl restart systemd-resolved

# Thay đổi DNS servers
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
echo "nameserver 8.8.4.4" | sudo tee -a /etc/resolv.conf
```

### Lỗi dung lượng disk
```bash
# Kiểm tra dung lượng
df -h

# Dọn dẹp cache
sudo apt clean
sudo apt autoremove

# Xóa logs cũ
sudo journalctl --vacuum-time=7d
```

### Lỗi permission
```bash
# Đảm bảo chạy với sudo
sudo ./install.sh

# Kiểm tra quyền files
ls -la install.sh
ls -la lib/
ls -la scripts/
```

## Debug chi tiết

### Bật debug mode
```bash
# Thêm debug vào script
export DEBUG=1
sudo ./install.sh
```

### Kiểm tra logs
```bash
# Xem logs installation
tail -f /tmp/squid_install.log

# Xem APT logs
tail -f /var/log/apt/history.log
```

### Test manual
```bash
# Test cài đặt từng package
sudo apt update
sudo apt install -y squid
sudo apt install -y apache2-utils
sudo apt install -y sqlite3

# Kiểm tra service
sudo systemctl status squid
```

## Troubleshooting dependencies

### Nếu không thể cài đặt squid:
```bash
# Thêm universe repository
sudo add-apt-repository universe
sudo apt update

# Cài đặt từ package cụ thể
sudo apt install squid squid-common
```

### Nếu apache2-utils không tìm thấy:
```bash
# Cài đặt alternative
sudo apt install apache2-bin
```

### Nếu sqlite3 không khả dụng:
```bash
# Cài đặt từ snap
sudo snap install sqlite3
```

## Kiểm tra sau cài đặt

```bash
# Kiểm tra service
sudo systemctl status squid

# Kiểm tra port
sudo netstat -tlnp | grep 8080

# Kiểm tra config
sudo squid -k parse

# Test proxy
curl -x localhost:8080 http://google.com
```

## Gỡ cài đặt hoàn toàn

```bash
# Sử dụng script uninstall
sudo ./install.sh
# Chọn option 8: Gỡ cài đặt Squid

# Hoặc manual:
sudo systemctl stop squid
sudo apt remove --purge squid squid-common apache2-utils
sudo rm -rf /etc/squid
sudo rm -rf /var/log/squid
sudo rm -rf /var/cache/squid
```

## Liên hệ hỗ trợ

Nếu vẫn gặp vấn đề, cung cấp thông tin sau:
1. Output của `./test_install.sh`
2. Content của `/tmp/squid_install.log`
3. Output của `sudo apt update`
4. Ubuntu version: `lsb_release -a` 