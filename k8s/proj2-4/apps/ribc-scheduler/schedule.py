import logging
import os
import time

import psycopg2

INPUT_FOLDER = os.environ["INPUT_FOLDER"]
OUTPUT_FOLDER = os.environ["OUTPUT_FOLDER"]
PGCONNINFO = os.environ["PGCONNINFO"]

logger = logging.getLogger(__name__)

def scheduler():
    logger.info("Running scheduler...")
    time.sleep(10)
    logger.info("Done.")

if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
    )
    
    scheduler()
