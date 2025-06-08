import os
import yaml
import logging
import mlflow
import torch
from transformers import (
    AutoModelForCausalLM,
    AutoTokenizer,
    Trainer,
    TrainingArguments,
    DataCollatorForLanguageModeling,
)
from datasets import load_dataset
from typing import Dict, Any
from pathlib import Path

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class ModelTrainer:
    def __init__(self, config_path: str):
        """Initialize the model trainer with configuration."""
        self.config = self._load_config(config_path)
        self.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        
        # Initialize MLflow
        mlflow.set_tracking_uri(self.config["mlflow"]["tracking_uri"])
        mlflow.set_experiment(self.config["mlflow"]["experiment_name"])
        
        # Initialize model and tokenizer
        self.model = self._load_model()
        self.tokenizer = self._load_tokenizer()
        
        # Set up data collator
        self.data_collator = DataCollatorForLanguageModeling(
            tokenizer=self.tokenizer,
            mlm=False
        )

    def _load_config(self, config_path: str) -> Dict[str, Any]:
        """Load configuration from YAML file."""
        with open(config_path, 'r') as f:
            config = yaml.safe_load(f)
        return config

    def _load_model(self) -> AutoModelForCausalLM:
        """Load pre-trained model."""
        logger.info(f"Loading model: {self.config['model']['name']}")
        model = AutoModelForCausalLM.from_pretrained(
            self.config["model"]["name"],
            trust_remote_code=True
        )
        return model.to(self.device)

    def _load_tokenizer(self) -> AutoTokenizer:
        """Load tokenizer."""
        logger.info(f"Loading tokenizer: {self.config['model']['name']}")
        return AutoTokenizer.from_pretrained(
            self.config["model"]["name"],
            trust_remote_code=True
        )

    def _prepare_dataset(self):
        """Prepare dataset for training."""
        logger.info("Loading and preparing dataset")
        dataset = load_dataset(
            self.config["data"]["name"],
            split=self.config["data"]["split"]
        )
        
        def tokenize_function(examples):
            return self.tokenizer(
                examples["text"],
                truncation=True,
                padding="max_length",
                max_length=self.config["data"]["max_length"]
            )
        
        tokenized_dataset = dataset.map(
            tokenize_function,
            batched=True,
            remove_columns=dataset.column_names
        )
        
        return tokenized_dataset

    def train(self):
        """Train the model with MLflow tracking."""
        logger.info("Starting training process")
        
        # Prepare dataset
        train_dataset = self._prepare_dataset()
        
        # Set up training arguments
        training_args = TrainingArguments(
            output_dir=self.config["training"]["output_dir"],
            num_train_epochs=self.config["training"]["num_epochs"],
            per_device_train_batch_size=self.config["training"]["batch_size"],
            warmup_steps=self.config["training"]["warmup_steps"],
            weight_decay=self.config["training"]["weight_decay"],
            logging_dir=self.config["training"]["logging_dir"],
            logging_steps=self.config["training"]["logging_steps"],
            save_strategy="epoch",
            evaluation_strategy="epoch"
        )
        
        # Initialize trainer
        trainer = Trainer(
            model=self.model,
            args=training_args,
            train_dataset=train_dataset,
            data_collator=self.data_collator,
        )
        
        # Start MLflow run
        with mlflow.start_run() as run:
            # Log parameters
            mlflow.log_params({
                "model_name": self.config["model"]["name"],
                "batch_size": self.config["training"]["batch_size"],
                "num_epochs": self.config["training"]["num_epochs"],
                "learning_rate": self.config["training"]["learning_rate"],
            })
            
            # Train model
            try:
                train_result = trainer.train()
                
                # Log metrics
                mlflow.log_metrics({
                    "train_loss": train_result.training_loss,
                    "train_runtime": train_result.metrics["train_runtime"],
                })
                
                # Save model
                model_path = os.path.join(
                    self.config["training"]["output_dir"],
                    "final_model"
                )
                self.model.save_pretrained(model_path)
                self.tokenizer.save_pretrained(model_path)
                
                # Log model to MLflow
                mlflow.transformers.log_model(
                    transformers_model={
                        "model": self.model,
                        "tokenizer": self.tokenizer
                    },
                    artifact_path="model",
                )
                
                logger.info(f"Training completed. Model saved to {model_path}")
                logger.info(f"MLflow run ID: {run.info.run_id}")
                
            except Exception as e:
                logger.error(f"Training failed: {str(e)}")
                raise

    def evaluate(self):
        """Evaluate the model."""
        logger.info("Starting evaluation")
        # Add evaluation logic here
        pass

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Train a language model")
    parser.add_argument(
        "--config",
        type=str,
        default="configs/training.yaml",
        help="Path to configuration file"
    )
    args = parser.parse_args()
    
    trainer = ModelTrainer(args.config)
    trainer.train() 