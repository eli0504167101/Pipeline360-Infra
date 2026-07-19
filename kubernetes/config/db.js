// config/db.js
const mongoose = require('mongoose');

const connectDB = async () => {
    try {
        console.log("Connecting to MongoDB at:", process.env.MONGO_URL);
        await mongoose.connect(process.env.MONGO_URL, {
            serverSelectionTimeoutMS: 5000 // ניסיון התחברות ל-5 שניות בלבד כדי לא להיתקע
        });
        console.log("MongoDB Connected Successfully");
    } catch (err) {
        console.error("MongoDB Connection Failed:", err.message);
        process.exit(1); // אם אין חיבור ל-DB, האפליקציה לא יכולה לעבוד
    }
};

module.exports = connectDB;