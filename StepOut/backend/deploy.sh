#!/bin/bash
cd /Users/bharath/Desktop/events/StepOut/backend

echo "Deploying Firebase Functions and Firestore Indexes..."
echo "=========================================="

firebase deploy --only functions,firestore:indexes

echo ""
echo "Deployment complete!"
echo "If you see an index creation URL, click it to create the index manually."
