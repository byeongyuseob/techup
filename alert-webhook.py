#!/usr/bin/env python3
from flask import Flask, request, jsonify
from datetime import datetime

app = Flask(__name__)

@app.route('/webhook', methods=['POST'])
def webhook():
    data = request.json
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{timestamp}] Alert received:")
    print(f"  Status: {data.get('status')}")
    for alert in data.get('alerts', []):
        print(f"  - Alert: {alert.get('labels', {}).get('alertname')}")
        print(f"    Status: {alert.get('status')}")
        print(f"    Summary: {alert.get('annotations', {}).get('summary')}")
        print(f"    Description: {alert.get('annotations', {}).get('description')}")
        print("    ---")
    return jsonify({"status": "success"}), 200

@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "healthy"}), 200

if __name__ == '__main__':
    print("Alert webhook server starting on port 5001...")
    app.run(host='0.0.0.0', port=5001)
