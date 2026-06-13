# set-up-speedtest-x

在你的服务器上自动搭建一个测速的网页 https://github.com/MortyFx/speedtest-x
需要你使用你电脑上的浏览器来访问网页测试,从而得到更加真实实际的网络信息
**注意已经安装了宝塔面板之类的直接用面板部署，不要用此脚本，可能会导致问题
使用方法
```bash
bash <(curl -LsS https://raw.githubusercontent.com/fanchuanhah/set-up-speedtest-x/refs/heads/main/install.sh)
```
输入运行端口（默认33332），会检测是否被占用，可以自定义端口
然后脚本便会自动安装
已测试：
ubuntu20-24,debian9-12,centos9,alpine
删除方法（用宝塔面板部署的不要这样删除）
```bash
bash <(curl -LsS https://raw.githubusercontent.com/fanchuanhah/set-up-speedtest-x/refs/heads/main/install.sh) uninstall
```
国内使用
```bash
bash <(curl -LsS https://ghfast.top/https://raw.githubusercontent.com/fanchuanhah/set-up-speedtest-x/refs/heads/main/install.sh)
```
