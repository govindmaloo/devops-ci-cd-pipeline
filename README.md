# Student Registration System

A simple **Flask** web application to manage student records with **MongoDB** as the backend database. Users can **add, view, update, and delete** student details.

---

## Features

* List all students on the home page
* Add a new student
* Update existing student details
* Delete a student with confirmation
* Simple and responsive UI using Bootstrap

---

## Tech Stack

* **Backend:** Python, Flask
* **Database:** MongoDB (via Flask-PyMongo)
* **Frontend:** HTML, Jinja2 templates, Bootstrap 5
* **Environment Variables:** Managed via `.env` file

---

## Setup Instructions

### 1. Clone the repository

```bash
git clone <your-repo-url>
cd <repo-folder>
```

### 2. Create and activate a virtual environment

```bash
python -m venv venv
# Activate venv
# Windows:
venv\Scripts\activate
# Linux / Mac:
source venv/bin/activate
```

### 3. Install dependencies

```bash
pip install -r requirements.txt
```

**`requirements.txt` example:**

```
Flask
Flask-PyMongo
python-dotenv
bson
```

### 4. Configure environment variables

Create a `.env` file in the project root:

```
MONGO_URI=<your-mongodb-connection-string>
SECRET_KEY=<your-secret-key>
```

### 5. Run the application

```bash
python app.py
```

Open your browser at: [http://localhost:8000](http://localhost:8000)

---

## Project Structure

```
project/
│
├── templates/
│   ├── base.html
│   ├── index.html
│   ├── add_student.html
│   ├── update_student.html
│
├── app.py
├── requirements.txt
└── .env
```

---

## Screenshots

**Home Page**
Lists all students with Edit/Delete buttons.
- <img width="1902" height="607" alt="image" src="https://github.com/user-attachments/assets/a58a6a6d-4978-4769-8074-232e4d31e69d" />


**Add Student**
Form to add a new student.
- <img width="1897" height="801" alt="image" src="https://github.com/user-attachments/assets/d65d25c3-ebb5-410a-adb1-e130ad7c5878" />


**Update Student**
Form pre-filled with student details.
- <img width="1905" height="897" alt="image" src="https://github.com/user-attachments/assets/04febf01-879f-431f-ab07-abcfb993acf1" />



---

## Notes

* Make sure MongoDB is running and accessible via the URI in `.env`
* Delete action includes a confirmation page to prevent accidental deletion
* Uses `ObjectId` from `bson` to work with MongoDB document IDs
* If you use MongoDB Atlas on macOS, install dependencies again (`pip install -r requirements.txt`). This project now uses `certifi` CA bundle explicitly to avoid common TLS certificate verification failures with `pymongo`.

---

## Jenkins CI/CD Pipeline

### Prerequisites

* EC2 instance (Ubuntu 22.04) — use `aws/setup.sh` to provision
* Jenkins running on port **8080**
* MongoDB running on port **27017**
* Security group ports: 22, 8080, 5000

### Quick EC2 + Jenkins setup

```bash
# From your local machine
./aws/setup.sh

# Configure Jenkins pipeline on EC2
ssh -i ~/Downloads/jenkins-flask-key.pem ubuntu@<EC2_IP>
cd devops-ci-cd-pipeline && git pull
sudo bash scripts/setup-jenkins-pipeline.sh
```

### Pipeline stages

| Stage | Action |
|-------|--------|
| **Build** | `pip install -r requirements.txt` |
| **Test** | `pytest test_app.py` (requires MongoDB) |
| **Deploy** | Copies app to staging, starts Flask on port **5000** |

### Jenkins access

* URL: `http://<EC2_PUBLIC_IP>:8080`
* Default admin (after setup script): `admin` / `Jenkins@2026`
* Pipeline job name: `flask-pipeline`

### Triggers

The `Jenkinsfile` uses **Poll SCM** (`H/2 * * * *`) — Jenkins checks GitHub every 2 minutes for changes on `main`.

### Email notifications

Configure SMTP in Jenkins → **Manage Jenkins → System → Extended E-mail Notification**, then set your email in the Jenkinsfile `post` block or as `NOTIFICATION_EMAIL` env var in the job.

### Staging URL

After a successful deploy: `http://<EC2_PUBLIC_IP>:5000`

---

## License

MIT License

---



