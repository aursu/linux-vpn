# linux-vpn

Cisco AnyConnect VPN client scripts

### Requirements

1. `openconnect` package should be installed (eg `yum install openconnect` on CentOS 7)
2. content of this repository should be copied into `/usr/local/sbin/vpn`, `/usr/lib/systemd/system` and `/etc/vpn` accordingly

### Settings

1. Optionally could be installed Post coneection script /etc/vpnc/post-connect.d/01-workenv
2. Optionally could be adjusted logging settings for charon IKE daemon using settings from /etc/strongswan.d/charon-logging.conf 

### Setup

1. `/etc/vpn/vpn-login-<VPN service name>` should be set with correct credentials

2. enable and start authentication service:
    ```
    systemctl enable vpnauth@<VPN service name>
    systemctl start vpnauth@<VPN service name>
    ```

3. enable and start VPN client:
    ```
    systemctl enable vpnrun@<VPN service name>
    systemctl start vpnrun@<VPN service name>
    ```
