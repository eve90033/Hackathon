extends Resource
class_name ResourceMonsterBehavior

## 怪物行為模板資源：定義三種 AI 類型的參數

enum Type { BASIC, DASH, FLANK }

@export var type: Type = Type.BASIC
@export var charge_time: float = 0.3
@export var lunge_speed_mult: float = 3.0
@export var retreat_speed_mult: float = 2.5
