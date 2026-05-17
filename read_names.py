import csv

try:
    with open("MOCK_DATA.csv", newline="") as f:
        reader = csv.DictReader(f)
        if not {"first_name", "last_name"}.issubset(reader.fieldnames or []):
            raise ValueError(f"Missing required columns. Found: {reader.fieldnames}")
        for row in reader:
            print(f"{row['first_name']} {row['last_name']}")
except FileNotFoundError:
    print("Error: MOCK_DATA.csv not found. Make sure it's in the current directory.")
except ValueError as e:
    print(f"Error: {e}")
except csv.Error as e:
    print(f"Error reading CSV: {e}")
