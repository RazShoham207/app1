from flask import Flask, request, jsonify, make_response, send_from_directory, render_template
from urllib.parse import quote as url_quote
from datetime import datetime
from collections import OrderedDict
import json
import os

app = Flask(__name__)

class Restaurant:
    def __init__(self, name, style, address, open_hour, close_hour, vegetarian, deliveries):
        self.name = name
        self.style = style
        self.address = address
        self.open_hour = open_hour
        self.close_hour = close_hour
        self.vegetarian = vegetarian
        self.deliveries = deliveries

    def is_open(self, current_time):
        open_time = datetime.strptime(self.open_hour, "%H:%M").time()
        close_time = datetime.strptime(self.close_hour, "%H:%M").time()
        
        if open_time < close_time:
            # Opening and closing times are on the same day
            return open_time <= current_time <= close_time
        else:
            # Opening and closing times are on different days
            return current_time >= open_time or current_time <= close_time

restaurants = [
    Restaurant("Pizza Hut", "Italian", "123 Main St", "09:00", "23:00", False, True),
    Restaurant("Veggie Delight", "Vegetarian", "456 Elm St", "10:00", "22:00", True, True),
    Restaurant("Sushi World", "Japanese", "789 Oak St", "11:00", "21:00", False, False),
    Restaurant("Late Night Diner", "American", "101 Night St", "10:00", "02:00", False, True),
    Restaurant("Very Late Night Diner", "American", "222 Night St", "11:00", "03:00", False, True),
    Restaurant("Very very Late Night Diner", "American", "333 Night St", "12:00", "04:00", False, True),
    Restaurant("Very very Late Night Diner", "American", "333 Night St", "12:00", "05:00", False, True),
    Restaurant("Day time", "American", "333 Night St", "08:00", "16:00", False, True),
    # Add more restaurants as needed
]

@app.route('/recommend', methods=['GET'])
def recommend_restaurant():
    style = request.args.get('style')
    vegetarian = request.args.get('vegetarian')
    current_time = datetime.now().time()

    recommendations = []
    for restaurant in restaurants:
        if style and restaurant.style.lower() != style.lower():
            continue
        if vegetarian and str(restaurant.vegetarian).lower() != vegetarian.lower():
            continue
        if restaurant.is_open(current_time):
            recommendation = OrderedDict([
                ("name", restaurant.name),
                ("style", restaurant.style),
                ("address", restaurant.address),
                ("openHour", restaurant.open_hour),
                ("closeHour", restaurant.close_hour),
                ("vegetarian", restaurant.vegetarian)
            ])
            recommendations.append(recommendation)
    
    print(f"Recommendations: {recommendations}")  # Debugging statement

    if recommendations:
        return render_template('index.html', data=json.dumps({"restaurantRecommendations": recommendations}, indent=4))
    return jsonify({"message": "No matching restaurant found"}), 404

@app.route('/favicon.ico')
def favicon():
    response = make_response(send_from_directory(os.path.join(app.root_path, 'static'),
                               'favicon.ico', mimetype='image/vnd.microsoft.icon'))
    response.headers['Cache-Control'] = 'public, max-age=86400'  # Cache for 1 day
    return response

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80)
