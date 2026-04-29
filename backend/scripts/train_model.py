import os
import random
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score
import joblib

def generate_synthetic_data(num_samples=1000):
    X = []
    y = []
    
    for _ in range(num_samples):
        # Features
        edad = random.randint(3, 12)
        nivel_cognitivo = random.choice([0, 1, 2])  # 0=Bajo, 1=Medio, 2=Alto
        num_sensibilidades = random.randint(0, 10)
        num_objetivos = random.randint(1, 5)
        
        # Rule-based target (Dificultad: 0=Básico, 1=Intermedio, 2=Avanzado)
        # We add some noise so it's not a perfect rule
        
        score = (nivel_cognitivo * 2) + (edad / 6) - (num_sensibilidades * 0.5)
        
        if score < 1.0:
            dificultad = 0  # Básico
        elif score > 3.0:
            dificultad = 2  # Avanzado
        else:
            dificultad = 1  # Intermedio
            
        # Add slight noise to simulate real-world fuzziness (10% chance to flip to adjacent)
        if random.random() < 0.1:
            if dificultad == 0:
                dificultad = 1
            elif dificultad == 2:
                dificultad = 1
            else:
                dificultad = random.choice([0, 2])
                
        X.append([edad, nivel_cognitivo, num_sensibilidades, num_objetivos])
        y.append(dificultad)
        
    return np.array(X), np.array(y)

def main():
    print("Generando dataset sintético...")
    X, y = generate_synthetic_data(1500)
    
    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)
    
    print("Entrenando RandomForestClassifier...")
    model = RandomForestClassifier(n_estimators=100, max_depth=5, random_state=42)
    model.fit(X_train, y_train)
    
    y_pred = model.predict(X_test)
    acc = accuracy_score(y_test, y_pred)
    
    print(f"✅ Accuracy del modelo: {acc * 100:.2f}%")
    
    if acc >= 0.85:
        # Save model
        output_dir = os.path.join(os.path.dirname(__file__), "..", "app", "ai", "models")
        os.makedirs(output_dir, exist_ok=True)
        
        model_path = os.path.join(output_dir, "rf_dificultad.pkl")
        joblib.dump(model, model_path)
        print(f"Modelo exportado exitosamente a {model_path}")
    else:
        print("❌ El modelo no alcanzó el 85% de precisión requerido.")

if __name__ == "__main__":
    main()
