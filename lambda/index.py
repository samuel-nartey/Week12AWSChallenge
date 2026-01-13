import json
import boto3
import logging
import os

# Initialize logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3_client = boto3.client('s3')
translate_client = boto3.client('translate')

def lambda_handler(event, context):
    logger.info("Received event: " + json.dumps(event))

    # 1. Extract bucket name and object key from the S3 event
    try:
        record = event['Records'][0]['s3']
        source_bucket = record['bucket']['name']
        source_key = record['object']['key']
        logger.info(f"Processing file: s3://{source_bucket}/{source_key}")
    except KeyError as e:
        logger.error(f"Failed to parse S3 event: {e}")
        raise e

    # 2. Retrieve and read the object from S3
    try:
        response = s3_client.get_object(Bucket=source_bucket, Key=source_key)
        file_content = response['Body'].read().decode('utf-8')
        translation_request = json.loads(file_content)
        logger.info(f"Raw file content: {file_content}")
    except Exception as e:
        logger.error(f"Error reading from S3: {e}")
        raise e

    # 3. Validate and extract translation parameters from the NEW JSON format
    try:
        text_to_translate = translation_request['Text']  # Direct access, not [0]
        source_lang = translation_request['SourceLanguageCode']
        target_langs = translation_request['TargetLanguageCodes']  # Now a list
        logger.info(f"Text to translate: {text_to_translate}")
        logger.info(f"Source language: {source_lang}")
        logger.info(f"Target languages: {target_langs}")
        
        # Validate that target_langs is a list
        if not isinstance(target_langs, list):
            raise ValueError("TargetLanguageCodes must be a list of language codes.")
            
    except (KeyError, ValueError) as e:
        logger.error(f"Invalid JSON structure in input file: {e}")
        raise e

    # 4. Get the output bucket from environment variable
    destination_bucket = os.environ['OUTPUT_BUCKET']
    logger.info(f"Destination bucket: {destination_bucket}")

    # 5. Loop through each target language and call AWS Translate
    for target_lang in target_langs:
        try:
            logger.info(f"Translating to: {target_lang}")
            translate_response = translate_client.translate_text(
                Text=text_to_translate,
                SourceLanguageCode=source_lang,
                TargetLanguageCode=target_lang
            )
            translated_text = translate_response['TranslatedText']
            logger.info(f"Translated text ({target_lang}): {translated_text}")

        except Exception as e:
            logger.error(f"Error calling Translate for {target_lang}: {e}")
            continue  # Skip this language and continue with the next

        # 6. Prepare the output for each language
        # Create a new key for the output file, appending the language code
        # e.g., 'input/file.json' -> 'output/file_es.json'
        original_filename = source_key.split('/')[-1]  # Gets 'myfile.json'
        name_without_extension = original_filename.rsplit('.', 1)[0]  # Gets 'myfile'
        output_key = f"output/{name_without_extension}_{target_lang}.json"

        output_data = {
            "original_text": text_to_translate,
            "translated_text": translated_text,
            "source_language": source_lang,
            "target_language": target_lang
        }

        # 7. Write the result for this language to the destination bucket
        try:
            s3_client.put_object(
                Bucket=destination_bucket,
                Key=output_key,
                Body=json.dumps(output_data, ensure_ascii=False, indent=2)
            )
            logger.info(f"Successfully written to: s3://{destination_bucket}/{output_key}")
        except Exception as e:
            logger.error(f"Error writing to S3 for {target_lang}: {e}")
            # Decide if you want to continue or fail here

    return {
        'statusCode': 200,
        'body': json.dumps(f'Processing complete. Translated to {len(target_langs)} language(s).')
    }