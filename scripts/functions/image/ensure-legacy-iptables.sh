ensure_legacy_iptables() {
  echo "🛠 Ensuring legacy iptables backend is active..."

  sudo update-alternatives --set iptables /usr/sbin/iptables-legacy
  sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy

  echo "✔ iptables backend set to legacy"
}
