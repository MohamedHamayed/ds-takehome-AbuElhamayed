# Data Science Take-Home — Procurement & Supply Analytics
This repository contains my solution for the Data Science Take-Home Exercise focused on Procurement & Supply Analytics.
It includes Exploratory Data Analysis, Anomaly Detection Modeling, and SQL Solutions.

---

## Repository Structure
```bash
.
├── notebooks/
│   ├── EDA.ipynb
│   ├── Model_Anomaly.ipynb
├── sql/
│   └── sql_exercise.sql
└── requirements.txt
```

---

## Environment Setup
To ensure a smooth setup, follow these steps:

### 1. Clone the repository
```bash
git clone ds-takehome-AbuElhamayed
cd ds-takehome-AbuElhamayed
```
### 2. Create a Virtual Environment
```bash
python3 -m venv venv
source venv/bin/activate  # On Linux/Mac
venv\Scripts\activate     # On Windows
```
### 3. Install Dependencies
```bash
pip install --upgrade pip
pip install -r requirements.txt
```
---

## How to Run the Notebooks
### 1. Start Jupyter Notebook
`jupyter notebook`

### 2. Open and Run
- Navigate to notebooks/EDA.ipynb
→ Perform EDA and data quality checks (visuals & narratives included).
- Navigate to notebooks/Model_Anomaly.ipynb
→ Perform modeling, evaluation, calibration, and anomaly detection.

---

## SQL Tasks
The file sql/sql_exercise.sql contains solutions to all SQL questions provided in the exercise.
You can execute them using your preferred SQL environment (e.g., PostgreSQL, MySQL, or SQLite).

---

## Deliverables
- EDA & Data Quality Analysis → `notebooks/EDA.ipynb`
- Anomaly Detection Model → `notebooks/Model_Anomaly.ipynb`
- SQL Solutions → `sql/sql_exercise.sql`

---

## Requirements
- Python 3.10+
- Jupyter Notebook
- Libraries in requirements.txt (e.g., pandas, numpy, matplotlib, seaborn, scikit-learn)
