# 1. Buat direktori kerja baru (biar rapi)
mkdir -p /opt/pterodactyl-protect
cd /opt/pterodactyl-protect

# 2. Clone repo kamu (pastikan branch main benar)
git clone https://github.com/mwildanhidayat/bocah-lihat-gjelsii.git .

# 3. Masuk ke folder repo
# Pastikan kamu masih di /opt/pterodactyl-protect
pwd   # harus output: /opt/pterodactyl-protect

# Cek isi (seharusnya sudah ada Protect-panel dan install.sh)
ls -la

# Jalankan installer langsung dari sini
bash install.sh
