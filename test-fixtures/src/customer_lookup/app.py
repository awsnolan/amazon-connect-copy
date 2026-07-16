"""
Lambda: dr-test-customer-lookup

Called by Amazon Connect contact flow to look up a customer by phone number.
Reads from DynamoDB table specified in TABLE_NAME env var.

Input (from Connect):
  event['Details']['ContactData']['CustomerEndpoint']['Address'] = "+61400000000"

Output (returned to Connect):
  {"CustomerName": "Jane Smith", "AccountTier": "Premium", "Language": "en-AU"}
"""

import os
import boto3
from boto3.dynamodb.conditions import Key

TABLE_NAME = os.environ.get("TABLE_NAME", "dr-test-customers")
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(TABLE_NAME)


def handler(event, context):
    # Extract phone number from Connect contact data
    phone = (
        event.get("Details", {})
        .get("ContactData", {})
        .get("CustomerEndpoint", {})
        .get("Address", "")
    )

    if not phone:
        return {
            "CustomerName": "Unknown",
            "AccountTier": "Standard",
            "Language": "en-AU",
        }

    # Look up customer
    try:
        response = table.get_item(Key={"PhoneNumber": phone})
        item = response.get("Item", {})
        return {
            "CustomerName": item.get("CustomerName", "Unknown"),
            "AccountTier": item.get("AccountTier", "Standard"),
            "Language": item.get("Language", "en-AU"),
        }
    except Exception:
        return {
            "CustomerName": "Unknown",
            "AccountTier": "Standard",
            "Language": "en-AU",
        }
