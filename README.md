# Squid HTTP Proxy Server Manager

## Giới thiệu

Đây là bộ script quản lý Squid HTTP proxy server, được thiết kế để dễ dàng cài đặt và quản lý proxy HTTP với xác thực trên VPS. Script hỗ trợ các hệ điều hành Ubuntu, Debian và CentOS.

Script gốc được phát triển bởi akmaslov-dev cho Dante SOCKS5 và được chuyển đổi hoàn toàn sang Squid HTTP proxy bởi ThienTranJP. Phiên bản hiện tại được cải tiến với cấu trúc module hóa, database SQLite và các tính năng quản lý nâng cao.

## Tính năng

- **Cài đặt tự động**: Cài đặt Squid HTTP proxy server với xác thực hoàn toàn tự động
- **Quản lý proxy user nâng cao**:
  - Thêm user mới với cấu hình tùy chỉnh
  - Thêm ngẫu nhiên nhiều user với các thông số đồng nhất
  - Xóa user cụ thể hoặc tất cả user
  - Cập nhật giới hạn bandwidth và quota cho từng user
- **Giới hạn và kiểm soát**:
  - Giới hạn tốc độ (bandwidth) cho từng user
  - Giới hạn quota dữ liệu hàng tháng
  - Monitoring và thống kê sử dụng real-time
- **Database và Backup**:
  - Lưu trữ thông tin user trong database SQLite
  - Backup và restore database
  - Export danh sách proxy với nhiều định dạng
- **Monitoring và Thống kê**:
  - Xem thống kê sử dụng chi tiết
  - Traffic monitoring theo user
  - System health monitoring
- **Bảo mật và Privacy**:
  - Xác thực username/password an toàn
  - Ẩn thông tin proxy headers
  - Traffic control và firewall integration
- **Quản lý dịch vụ**:
  - Kiểm tra trạng thái dịch vụ
  - Khởi động lại dịch vụ
  - Log management và cleanup
  - Gỡ cài đặt hoàn toàn

## Yêu cầu hệ thống

- **Hệ điều hành**: Ubuntu 18.04+, Debian 9+, hoặc CentOS 7+
- **Quyền root**: Cần thiết để cài đặt và cấu hình
- **Bash shell**: Version 4.0 trở lên
- **RAM**: Tối thiểu 512MB, khuyến nghị 1GB+
- **Disk**: Tối thiểu 1GB trống
- **Network**: Kết nối internet ổn định

## Cài đặt

1. **Tải về repository**:
   ```bash
   git clone https://github.com/thien-tn/ProxySquid.git
   cd ProxySquid
   ```

2. **Cấp quyền thực thi**:
   ```bash
   chmod +x install.sh
   chmod +x scripts/*.sh
   chmod +x lib/*.sh
   ```

3. **Chạy script cài đặt**:
   ```bash
   ./install.sh
   ```

4. **Cấu hình ban đầu**:
   - Script sẽ tự động phát hiện hệ điều hành
   - Cài đặt các dependencies cần thiết
   - Thiết lập database SQLite
   - Tạo cấu hình Squid tối ưu
   - Tạo user proxy đầu tiên với thông tin ngẫu nhiên

## Cách sử dụng

### Menu chính

Sau khi cài đặt, chạy script để truy cập menu quản lý:

```bash
./install.sh
```

### Các tính năng chính

**1. Quản lý Users**:
```bash
# Thêm user mới với cấu hình tùy chỉnh
./scripts/add_user.sh

# Thêm nhiều user ngẫu nhiên
./scripts/add_random_users.sh

# Xem danh sách user hiện có
./scripts/list_users.sh
```

**2. Monitoring và Thống kê**:
```bash
# Xem thống kê chi tiết
./scripts/show_statistics.sh

# Kiểm tra trạng thái hệ thống
./scripts/system_check.sh
```

**3. Backup và Export**:
```bash
# Backup database
./scripts/backup_database.sh

# Export danh sách proxy
./scripts/export_proxy_list.sh
```

**4. Quản lý dịch vụ**:
```bash
# Kiểm tra trạng thái dịch vụ
./scripts/check_status.sh

# Khởi động lại dịch vụ
./scripts/restart_service.sh
```

## Cấu trúc thư mục

```
ProxySquid/
├── install.sh                     # Script cài đặt và menu chính
├── README.md                      # Tài liệu hướng dẫn
├── config/                        # Thư mục cấu hình
│   └── squid.conf.template        # Template cấu hình Squid
├── lib/                           # Thư mục modules
│   ├── common.sh                  # Các hàm dùng chung
│   ├── check_environment.sh       # Kiểm tra môi trường
│   ├── install_squid.sh           # Cài đặt Squid
│   ├── setup_service.sh           # Thiết lập service
│   ├── user_management.sh         # Quản lý user proxy
│   └── uninstall.sh               # Gỡ cài đặt
└── scripts/                       # Thư mục scripts riêng lẻ
    ├── add_user.sh                # Thêm user
    ├── add_random_users.sh        # Thêm nhiều user ngẫu nhiên
    ├── delete_user.sh             # Xóa user
    ├── delete_all_users.sh        # Xóa tất cả user
    ├── list_users.sh              # Liệt kê user
    ├── update_bandwidth.sh        # Cập nhật bandwidth
    ├── update_quota.sh            # Cập nhật quota
    ├── export_proxy_list.sh       # Xuất danh sách proxy
    ├── show_statistics.sh         # Hiển thị thống kê
    ├── backup_database.sh         # Backup database
    ├── check_status.sh            # Kiểm tra trạng thái
    ├── restart_service.sh         # Khởi động lại dịch vụ
    ├── system_check.sh            # Kiểm tra hệ thống
    └── uninstall.sh               # Gỡ cài đặt
```

## Thông tin kỹ thuật

### Database Schema

```sql
-- Bảng users
CREATE TABLE users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE,
    password TEXT,
    bandwidth_limit INTEGER DEFAULT 0,    -- Mbit/s
    data_quota INTEGER DEFAULT 0,         -- bytes
    data_used INTEGER DEFAULT 0,          -- bytes
    status TEXT DEFAULT 'active',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_active DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Bảng traffic_log
CREATE TABLE traffic_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT,
    bytes_in INTEGER DEFAULT 0,
    bytes_out INTEGER DEFAULT 0,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

### Cấu hình Squid

- **Port mặc định**: 8080 (có thể tùy chỉnh)
- **Xác thực**: Basic authentication với htpasswd
- **Logging**: Combined format trong `/var/log/squid/`
- **Cache**: 256MB memory cache
- **Timeout**: Tối ưu cho performance và stability
- **Security**: Ẩn proxy headers, chặn thông tin rò rỉ

### Traffic Control

- **HTB (Hierarchical Token Bucket)**: Bandwidth limiting per user
- **Class-based**: Mỗi user có class riêng
- **Real-time**: Áp dụng ngay lập tức khi cập nhật

## Bảo mật

- **User isolation**: Mỗi proxy user có thông tin xác thực riêng
- **No shell access**: Users không có quyền login SSH
- **Password hashing**: Mật khẩu được hash an toàn
- **Privacy protection**: Ẩn thông tin proxy trong headers
- **Firewall integration**: Tự động cấu hình iptables/UFW
- **Secure storage**: Database và config files có quyền hạn chế

## Monitoring và Logs

### Log Files
- **Squid Access Log**: `/var/log/squid/access.log`
- **Squid Cache Log**: `/var/log/squid/cache.log`
- **System Log**: `/var/log/proxy-manager.log`

### Monitoring Features
- Real-time bandwidth usage
- Data quota tracking
- User activity monitoring
- System health checks
- Traffic statistics

## Troubleshooting

### Kiểm tra trạng thái dịch vụ
```bash
systemctl status squid
./scripts/check_status.sh
```

### Xem logs
```bash
tail -f /var/log/squid/access.log
tail -f /var/log/proxy-manager.log
```

### Test kết nối proxy
```bash
curl --proxy http://username:password@server_ip:port http://ifconfig.me
```

### Reset cấu hình
```bash
./scripts/uninstall.sh  # Chọn option gỡ cài đặt nhẹ
./install.sh            # Cài đặt lại
```

## Performance Tuning

### Tối ưu cho High Traffic
```bash
# Tăng file descriptors
echo "* soft nofile 65536" >> /etc/security/limits.conf
echo "* hard nofile 65536" >> /etc/security/limits.conf

# Tối ưu kernel parameters
echo "net.core.rmem_max = 134217728" >> /etc/sysctl.conf
echo "net.core.wmem_max = 134217728" >> /etc/sysctl.conf
sysctl -p
```

### Monitor Performance
```bash
# CPU và Memory usage
htop

# Network traffic
iftop

# Disk I/O
iotop
```

## Changelog

### Version 2.0 (Current)
- ✅ Chuyển đổi hoàn toàn từ Dante SOCKS5 sang Squid HTTP
- ✅ Thêm database SQLite để quản lý users
- ✅ Bandwidth limiting và quota management
- ✅ Advanced monitoring và statistics
- ✅ Backup và export functionality
- ✅ Improved security và privacy features
- ✅ Traffic control integration
- ✅ Enhanced user interface

### Version 1.0 (Dante SOCKS5)
- ⚠️ Legacy version với Dante SOCKS5
- ⚠️ Basic user management
- ⚠️ Simple proxy creation

## Support

### Báo lỗi
Nếu gặp vấn đề, vui lòng tạo issue tại GitHub repository với thông tin:
- Hệ điều hành và phiên bản
- Log files liên quan
- Các bước tái tạo lỗi

### Tính năng mới
Đóng góp ý tưởng và pull requests luôn được chào đón!

## Gỡ cài đặt hoàn toàn

```bash
./scripts/uninstall.sh
# Hoặc
cd /root && rm -rf ProxySquid
```

## Giấy phép

MIT License - Xem file LICENSE để biết chi tiết

---

**Phát triển bởi**: ThienTranJP  
**Dựa trên**: Script gốc của akmaslov-dev (Dante version)  
**Repository**: https://github.com/thien-tn/ProxySquid
