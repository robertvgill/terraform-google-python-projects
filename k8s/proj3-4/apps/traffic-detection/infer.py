import random
import time

class InferenceError(Exception):
    pass

def run_inference(image_file, image_format):

    if image_format not in {b"jpg", b"png"}:
        raise InferenceError("Invalid image format")

    time.sleep(0.5 + random.random())

    num_vehicles = random.randint(0, 35)
    confidence = random.random()    
    
    return num_vehicles, confidence
    