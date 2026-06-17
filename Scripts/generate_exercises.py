import csv
import random

# Dictionnaires de base pour générer des données cohérentes
categories_data = {
    "Poids du Corps": {
        "sub_categories": ["Pectoraux", "Dos", "Jambes", "Abdominaux", "Bras"],
        "diff": ["Debutant", "Intermediaire", "Avance"],
        "rep_min": [5, 8, 10, 15],
        "rep_max": [10, 15, 20, 50],
        "cal": [4.0, 5.0, 6.0, 8.0],
        "risk": ["Faible", "Moyen"]
    },
    "Musculation": {
        "sub_categories": ["Pectoraux", "Dos", "Jambes", "Epaules", "Bras"],
        "diff": ["Debutant", "Intermediaire", "Avance"],
        "rep_min": [3, 5, 8, 10],
        "rep_max": [5, 8, 12, 15],
        "cal": [5.0, 7.0, 9.0],
        "risk": ["Moyen", "Eleve"]
    },
    "Cardio": {
        "sub_categories": ["Endurance", "HIIT", "Agilite"],
        "diff": ["Debutant", "Intermediaire", "Avance"],
        "rep_min": [0], # Le cardio se base plus sur le temps
        "rep_max": [0],
        "cal": [8.0, 10.0, 12.0, 15.0],
        "risk": ["Faible", "Moyen"]
    }
}

prefixes = ["Variation de", "Super", "Intense", "Slow", "Explosif"]
base_exercises = ["Squat", "Pompes", "Tirage", "Crunch", "Fentes", "Developpe", "Souleve", "Course", "Saut", "Gainage"]
suffixes = ["Halteres", "Barre", "Kettlebell", "Poulie", "Bande Elastique", "Incline", "Decline", "Unilateral"]

def generate_exercises(num_entries):
    exercises = []
    for i in range(1, num_entries + 1):
        cat = random.choice(list(categories_data.keys()))
        data = categories_data[cat]
        
        # Génération d'un nom cohérent
        name = f"{random.choice(base_exercises)} {random.choice(suffixes)} {random.randint(1,99)}"
        if cat == "Cardio":
            name = f"Session {random.choice(['Sprint', 'Endurance', 'Fractionne'])} {i}"
        elif cat == "Poids du Corps":
            name = f"{random.choice(base_exercises)} {random.choice(['Saute', 'Claquee', 'Statique', 'Lent'])} {i}"
            
        sub_cat = random.choice(data["sub_categories"])
        diff = random.choice(data["diff"])
        
        rep_min = random.choice(data["rep_min"]) if cat != "Cardio" else None
        rep_max = random.choice(data["rep_max"]) if cat != "Cardio" else None
        
        dur = random.choice([30, 45, 60, 90, 120]) if cat != "Cardio" else random.choice([600, 1200, 1800])
        rest = random.choice([30, 60, 90, 120]) if cat != "Cardio" else 0
        
        cals = random.choice(data["cal"])
        risk = random.choice(data["risk"])
        
        # Gestion des progressions (liens aléatoires avec des IDs précédents)
        prev_prog = random.randint(1, max(1, i-1)) if i > 10 and random.random() > 0.5 else None
        next_prog = prev_prog + 1 if prev_prog else None

        exercises.append({
            "id": i,
            "name": name,
            "instructions": f"Instructions generees pour {name}. Gardez une bonne posture.",
            "short_description": f"Exercice de type {cat} ciblant {sub_cat}.",
            "category": cat,
            "sub_category": sub_cat,
            "image": f"img_{i}.png",
            "difficulty_level": diff,
            "rep_range_min": rep_min,
            "rep_range_max": rep_max,
            "recommended_duration_seconds": dur,
            "recommended_rest_seconds": rest,
            "estimated_calories_per_minute": cals,
            "range_of_motion": random.choice(["Complet", "Partiel", "Etendu"]),
            "injury_risk_level": risk,
            "next_progression_exercise": next_prog,
            "previous_progression_exercise": prev_prog
        })
    return exercises

# Génération et écriture dans un CSV
dataset = generate_exercises(500)
keys = dataset[0].keys()

with open('exercices_dataset.csv', 'w', newline='', encoding='utf-8') as output_file:
    dict_writer = csv.DictWriter(output_file, fieldnames=keys)
    dict_writer.writeheader()
    dict_writer.writerows(dataset)

print("Fichier exercices_dataset.csv généré avec succès avec 500 entrées !")