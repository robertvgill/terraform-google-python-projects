import logging
import os
import socket
import struct
import json

import infer

from google.cloud import pubsub_v1
from google.cloud import storage

logger = logging.getLogger(__name__)

MSG_INFER = 1
MSG_RESULT = 2
MSG_ERROR = 3

MSG_FORMAT = "!HB256p16p"
MSG_SIZE = struct.calcsize(MSG_FORMAT)

# Set Google Cloud project ID
project_id = ''

# Set Pub/Sub topic name
pubsub_topic_name = ''

# Set Cloud Storage bucket name
bucket_name = ''

# Initialize Pub/Sub and Storage clients
publisher = pubsub_v1.PublisherClient()
storage_client = storage.Client()

def format_error(msg_id, error_message):
    return struct.pack(
        "!HB256p16x",
        msg_id,
        MSG_ERROR,
        error_message.encode("ascii")
    )

def publish_message(msg_id, msg_type, msg_arg1, msg_arg2):
    # Create a dictionary representing the message
    message_data = {
        'msg_id': msg_id,
        'msg_type': msg_type,
        'msg_arg1': msg_arg1,
        'msg_arg2': msg_arg2
    }

    # Serialize the message to JSON
    json_message = json.dumps(message_data)

    # Publish the JSON message to the Pub/Sub topic
    topic_path = publisher.topic_path(project_id, pubsub_topic_name)
    future = publisher.publish(topic_path, json_message.encode())
    future.result()
    logger.info("Published message to Pub/Sub")

def upload_to_storage(file_path):
    # Upload the file to Cloud Storage
    bucket = storage_client.get_bucket(bucket_name)
    blob = bucket.blob(os.path.basename(file_path))
    blob.upload_from_filename(file_path)
    logger.info(f"File uploaded to Cloud Storage: {blob.name}")

def run_server(socket_path):

    sock = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
    sock.bind(socket_path)

    logger.info("Bound to %s" % socket_path)

    try:
        while True:

            msg, address = sock.recvfrom(MSG_SIZE)

            if address is None:
                logger.error("Client did not bind")
                continue

            try:
                msg_id, msg_type, msg_arg1, msg_arg2 = struct.unpack(
                    MSG_FORMAT,
                    msg
                )

            except struct.error:
                logger.exception("Received invalid message")
                continue

            print(f"Received message: msg_id={msg_id}, msg_type={msg_type}, msg_arg1={msg_arg1}, msg_arg2={msg_arg2}")

            if msg_type == MSG_INFER:
                try:
                    with open(msg_arg1, "rb") as image_file:
                        print(f"Running inference for message {msg_id}")
                        res1, res2 = infer.run_inference(
                            image_file, msg_arg2
                        )

                    # Publish the results to Pub/Sub
                    print(f"Publishing results for message {msg_id}")
                    publish_message(msg_id, MSG_RESULT, res1, res2)

                    logger.info("Ran inference for message %d" % msg_id)
                except (IOError, infer.InferenceError) as e:
                    logger.exception(
                        "Inference for message %d failed" % msg_id
                    )

                    # Publish an error message to Pub/Sub
                    error_message = "Inference failed"
                    print(f"Publishing error for message {msg_id}")
                    publish_message(msg_id, MSG_ERROR, error_message, '')

            else:
                logger.error("Message %d was invalid" % msg_id)

                # Publish an error message to Pub/Sub
                error_message = "Invalid message"
                print(f"Publishing error for invalid message {msg_id}")
                publish_message(msg_id, MSG_ERROR, error_message, '')
                
    finally:
        os.unlink(socket_path)

if __name__ == "__main__":
    # Create a Unix Datagram Socket
    socket_path = os.environ["SOCKET_PATH"]

    logging.basicConfig(
        level=logging.INFO,
    )

    run_server(socket_path)

