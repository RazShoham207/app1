import os
import json
from flask import Flask, request, jsonify, make_response, send_from_directory, render_template
from urllib.parse import quote as url_quote
from datetime import datetime
from collections import OrderedDict

app = Flask(__name__)
app.config['STORAGE_ACCOUNT_FQDN'] = os.getenv('STORAGE_ACCOUNT_FQDN', 'default_fqdn')

# The restaurantstfstatesa.file.core.windows.net FQDN
storage_account_fqdn = app.config['STORAGE_ACCOUNT_FQDN']

class Restaurant:
    def __init__(self, name, cuisine, address, opening_time, closing_time, vegetarian, delivery):
        self.name = name
        self.cuisine = cuisine
        self.address = address
        self.opening_time = opening_time
        self.closing_time = closing_time
        self.vegetarian = vegetarian
        self.delivery = delivery

    def is_open(self, current_time):
        open_time = datetime.strptime(self.opening_time, "%H:%M").time()
        close_time = datetime.strptime(self.closing_time, "%H:%M").time()
        
        if open_time < close_time:
            # Opening and closing times are on the same day
            return open_time <= current_time <= close_time
        else:
            # Opening and closing times are on different days
            return current_time >= open_time or current_time <= close_time

def load_restaurants():
    with open('restaurants.json', 'r') as file:
        data = json.load(file)
        return [Restaurant(**restaurant) for restaurant in data]

@app.route('/')
def index():
    restaurants = load_restaurants()
    return render_template('index.html', restaurants=restaurants)

# Directory to save request history
HISTORY_DIR = "/app/history"

@app.route('/recommend', methods=['GET'])
def recommend_restaurant():
    cuisine = request.args.get('cuisine')
    vegetarian = request.args.get('vegetarian')
    current_time = datetime.now().time()

    recommendations = []
    restaurants = load_restaurants()
    for restaurant in restaurants:
        if cuisine and restaurant.cuisine.lower() != cuisine.lower():
            continue
        if vegetarian and str(restaurant.vegetarian).lower() != vegetarian.lower():
            continue
        if restaurant.is_open(current_time):
            recommendation = OrderedDict([
                ("name", restaurant.name),
                ("cuisine", restaurant.cuisine),
                ("address", restaurant.address),
                ("opening_time", restaurant.opening_time),
                ("closing_time", restaurant.closing_time),
                ("vegetarian", restaurant.vegetarian),
                ("delivery", restaurant.delivery)
            ])
            recommendations.append(recommendation)
    
    print(f"Recommendations: {recommendations}")  # Debugging statement

    # Save request history
    save_request_history(cuisine, vegetarian, recommendations)

    if recommendations:
        return render_template('index.html', data=json.dumps({"restaurantRecommendations": recommendations}, indent=4))
    return jsonify({"message": "No matching restaurant found"}), 404

def save_request_history(cuisine, vegetarian, recommendations):
    if not os.path.exists(HISTORY_DIR):
        os.makedirs(HISTORY_DIR, exist_ok=True)
    
    history_file = os.path.join(HISTORY_DIR, "request_history.txt")
    with open(history_file, "a") as f:
        f.write(f"Time: {datetime.now()}, Cuisine: {cuisine}, Vegetarian: {vegetarian}, Recommendations: {recommendations}\n")

@app.route('/favicon.ico')
def favicon():
    response = make_response(send_from_directory(os.path.join(app.root_path, 'static'),
                               'favicon.ico', mimetype='image/vnd.microsoft.icon'))
    response.headers['Cache-Control'] = 'public, max-age=86400'  # Cache for 1 day
    return response

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=443, ssl_context=('/app/tls.crt', '/app/tls.key'), debug=True)
