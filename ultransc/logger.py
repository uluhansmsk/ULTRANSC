import logging
from pathlib import Path
from typing import Optional

_logger: Optional[logging.Logger] = None

def setup_logger(system_log_path: Path, error_log_path: Path) -> logging.Logger:
    global _logger
    if _logger is not None:
        return _logger
        
    logger = logging.getLogger("ultransc")
    logger.setLevel(logging.INFO)
    logger.propagate = False
    
    if logger.hasHandlers():
        logger.handlers.clear()
    
    formatter = logging.Formatter("[%(asctime)s] %(levelname)s: %(message)s", datefmt="%Y-%m-%d %H:%M:%S")
    
    # Console handler
    ch = logging.StreamHandler()
    ch.setFormatter(formatter)
    logger.addHandler(ch)
    
    # System log handler
    try:
        fh_sys = logging.FileHandler(system_log_path, encoding="utf-8")
        fh_sys.setLevel(logging.INFO)
        fh_sys.setFormatter(formatter)
        logger.addHandler(fh_sys)
    except OSError:
        pass
        
    # Error log handler
    try:
        fh_err = logging.FileHandler(error_log_path, encoding="utf-8")
        fh_err.setLevel(logging.ERROR)
        fh_err.setFormatter(formatter)
        logger.addHandler(fh_err)
    except OSError:
        pass
        
    _logger = logger
    return logger

def get_logger() -> logging.Logger:
    global _logger
    if _logger is None:
        # Fallback if accessed before setup
        return logging.getLogger("ultransc")
    return _logger
