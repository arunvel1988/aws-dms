import pymysql
import json
import os

def lambda_handler(event, context):
    source_db = os.getenv("SOURCE_DB")
    dest_db = os.getenv("DEST_DB")
    db_user = os.getenv("DB_USER")
    db_password = os.getenv("DB_PASSWORD")

    try:
        # Connect to Source DB
        source_conn = pymysql.connect(host=source_db, user=db_user, password=db_password, database="information_schema")
        dest_conn = pymysql.connect(host=dest_db, user=db_user, password=db_password, database="information_schema")

        with source_conn.cursor() as source_cursor, dest_conn.cursor() as dest_cursor:
            source_cursor.execute("SELECT table_name FROM tables WHERE table_schema = 'your_db_name'")
            source_tables = set([row[0] for row in source_cursor.fetchall()])

            dest_cursor.execute("SELECT table_name FROM tables WHERE table_schema = 'your_db_name'")
            dest_tables = set([row[0] for row in dest_cursor.fetchall()])

            if source_tables == dest_tables:
                return {"statusCode": 200, "message": "Schema matches, proceed with migration"}
            else:
                return {"statusCode": 400, "message": "Schema mismatch, aborting migration"}

    except Exception as e:
        return {"statusCode": 500, "message": str(e)}
