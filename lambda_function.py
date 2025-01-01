import boto3
import pandas as pd
import io
import os

s3 = boto3.client("s3")

def lambda_handler(event, context):
    bucket_name = os.environ.get("S3_BUCKET_NAME", "")
    if not bucket_name:
        return {"statusCode": 400, "body": "S3_BUCKET_NAME environment variable is not set."}

    try:
        # Fetch files from S3
        anxiety_obj = s3.get_object(Bucket=bucket_name, Key="SF_HOMELESS_ANXIETY.csv")
        demographics_obj = s3.get_object(Bucket=bucket_name, Key="SF_HOMELESS_DEMOGRAPHICS.csv")

        # Read CSV files into DataFrames
        df_anxiety = pd.read_csv(io.BytesIO(anxiety_obj["Body"].read()))
        df_demographics = pd.read_csv(io.BytesIO(demographics_obj["Body"].read()))

        # Debugging: Print column names
        print(f"Anxiety Columns: {df_anxiety.columns}")
        print(f"Demographics Columns: {df_demographics.columns}")

        # Normalize column names
        df_anxiety.columns = df_anxiety.columns.str.strip()
        df_demographics.columns = df_demographics.columns.str.strip()

        # Check for HID column
        if "HID" not in df_anxiety.columns or "HID" not in df_demographics.columns:
            return {"statusCode": 400, "body": "HID column is missing in one or both input files."}

        # Merge DataFrames
        merged_df = pd.merge(df_anxiety, df_demographics, on="HID")
        output_buffer = io.StringIO()
        merged_df.to_csv(output_buffer, index=False)
        output_buffer.seek(0)

        # Upload merged DataFrame to S3
        s3.put_object(Bucket=bucket_name, Key="processed/merged_data.csv", Body=output_buffer.getvalue())
        return {"statusCode": 200, "body": "Merged dataset uploaded successfully."}
    except Exception as e:
        print(f"An error occurred: {str(e)}")
        return {"statusCode": 500, "body": str(e)}
