from dataclasses import dataclass
from pathlib import Path


@dataclass
class Paths:
    root: Path

    @property
    def queue(self) -> Path:
        return self.root / "queue"

    @property
    def incoming(self) -> Path:
        return self.queue / "incoming"

    @property
    def links(self) -> Path:
        return self.queue / "links.txt"

    @property
    def processing(self) -> Path:
        return self.queue / "processing"

    @property
    def done(self) -> Path:
        return self.queue / "done"

    @property
    def failed(self) -> Path:
        return self.queue / "failed"

    @property
    def models(self) -> Path:
        return self.root / "models"

    @property
    def bin(self) -> Path:
        return self.root / "bin"

    @property
    def workspace(self) -> Path:
        return self.root / "workspace"

    @property
    def logs(self) -> Path:
        return self.root / "logs"

    @property
    def config_dir(self) -> Path:
        return self.root / "config"

    @property
    def model_json(self) -> Path:
        return self.models / "list.json"

    @property
    def system_log(self) -> Path:
        return self.logs / "system.log"

    @property
    def error_log(self) -> Path:
        return self.logs / "errors.log"

    @property
    def lock_dir(self) -> Path:
        return self.root / ".ultransc.lock"

    @property
    def config_file(self) -> Path:
        return self.config_dir / "default.conf"
