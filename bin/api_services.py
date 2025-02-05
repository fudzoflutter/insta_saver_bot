from flask import Flask, request, jsonify, render_template
import instaloader
import logging
import sqlite3
from datetime import datetime, timedelta

# Flask ilovasini yaratish
app = Flask(__name__)

# Log faylini sozlash
logging.basicConfig(filename='user_activity.log', level=logging.INFO, format='%(asctime)s - %(message)s')

# Ma'lumotlar bazasini yaratish
conn = sqlite3.connect('users.db', check_same_thread=False)
cursor = conn.cursor()

# Jadvalni yaratish (agar mavjud bo'lmasa)
cursor.execute('''
    CREATE TABLE IF NOT EXISTS user_activity (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_ip TEXT,
        url TEXT,
        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
    )
''')
conn.commit()

# Instaloader obyektini yaratish
L = instaloader.Instaloader()

# API endpointi: Instagram media yuklab olish
@app.route('/download', methods=['POST'])
def download_media():
    # JSON so'rovdan URL ni olish
    data = request.get_json()
    url = data.get('url')
    user_ip = request.remote_addr  # Foydalanuvchi IP manzili

    # Log fayliga yozish
    logging.info(f"IP: {user_ip}, URL: {url}")

    # Ma'lumotlar bazasiga yozish
    cursor.execute('INSERT INTO user_activity (user_ip, url) VALUES (?, ?)', (user_ip, url))
    conn.commit()

    try:
        if 'instagram.com' in url:
            shortcode = url.split('/')[-2]  # URL'dan shortcode ni olish
            post = instaloader.Post.from_shortcode(L.context, shortcode)

            # Fayllarni olish (rasm yoki video)
            media_urls = []
            if post.is_video:
                media_urls.append(post.video_url)  # Video uchun
            else:
                if post.typename == 'GraphImage':  # Bitta rasm uchun
                    media_urls.append(post.url)
                elif post.typename == 'GraphSidecar':  # Albom uchun
                    for node in post.get_sidecar_nodes():
                        if node.is_video:  # Agar video bo'lsa
                            media_urls.append(node.video_url)
                        else:  # Agar rasm bo'lsa
                            media_urls.append(node.display_url)

            return jsonify({"media_urls": media_urls})

    except Exception as e:
        return jsonify({"error": str(e)})

# Admin paneli
@app.route('/admin')
def admin_panel():
    # Log faylini o'qish
    try:
        with open('user_activity.log', 'r') as file:
            logs = file.readlines()
    except FileNotFoundError:
        logs = ["Log fayli topilmadi"]

    # Ma'lumotlar bazasidan ma'lumotlarni olish
    try:
        cursor.execute('SELECT * FROM user_activity')
        activities = cursor.fetchall()
    except sqlite3.OperationalError as e:
        activities = [("Ma'lumotlar bazasi xatosi", str(e))]

    return render_template('admin.html', logs=logs, activities=activities)

# Monitoring uchun endpoint
@app.route('/monitoring')
def monitoring():
    # Hozir faol foydalanuvchilarni olish
    cursor.execute('SELECT DISTINCT user_ip FROM user_activity')
    active_users = cursor.fetchall()

    return jsonify({"active_users": [user[0] for user in active_users]})

# Faol foydalanuvchilarni sanash uchun endpoint
@app.route('/active_users')
def active_users():
    # So'nggi 5 daqiqa ichida faol bo'lgan foydalanuvchilarni olish
    cursor.execute('''
        SELECT DISTINCT user_ip FROM user_activity
        WHERE timestamp >= datetime('now', '-5 minutes')
    ''')
    active_users = cursor.fetchall()

    return jsonify({"active_users": [user[0] for user in active_users]})

# Serverni ishga tushirish
if __name__ == '__main__':
    app.run(debug=True)