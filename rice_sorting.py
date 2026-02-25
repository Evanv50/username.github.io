import time
import os
import ctypes
import numpy as np
import cv2
from thorlabs_tsi_sdk.tl_camera import TLCameraSDK

# ====== ThorCam DLL 环境 (保持不变) ======
THORCAM_DIR = r"C:\Program Files\Thorlabs\Scientific Imaging\ThorCam"
os.environ["PATH"] = THORCAM_DIR + ";" + os.environ.get("PATH", "")
if hasattr(os, 'add_dll_directory'):
    os.add_dll_directory(THORCAM_DIR)
ctypes.WinDLL(os.path.join(THORCAM_DIR, "thorlabs_tsi_camera_sdk.dll"))

# 2. 图像固定参数设置 (保持不变)
# ==============================================================================
FIXED_GAIN_R    = 2.20
FIXED_GAIN_G    = 1.00
FIXED_GAIN_B    = 2.05

FIXED_CONTRAST  = 1.00
FIXED_SATURATION= 2.10
FIXED_GAMMA     = 3.0

EXPOSURE_TIME   = 90000

# ==============================================================================
# 3. 图像处理逻辑 (原有基础增强)
# ==============================================================================
def apply_fixed_processing(img):
    # 1. 归一化 (0-1)
    if img.dtype != np.uint8:
        data = img.astype(np.float32) / 4095.0
    else:
        data = img.astype(np.float32) / 255.0

    # 2. 白平衡
    gains = np.array([FIXED_GAIN_B, FIXED_GAIN_G, FIXED_GAIN_R], dtype=np.float32)
    data = data * gains

    # 3. 饱和度
    gray = cv2.cvtColor(data, cv2.COLOR_BGR2GRAY)
    gray_3ch = cv2.cvtColor(gray, cv2.COLOR_GRAY2BGR)
    data = cv2.addWeighted(data, FIXED_SATURATION, gray_3ch, 1.0 - FIXED_SATURATION, 0)

    # 4. 对比度
    data = (data - 0.5) * FIXED_CONTRAST + 0.5

    # 5. Clip & Gamma
    data = np.clip(data, 0, 1)
    if FIXED_GAMMA != 1.0 and FIXED_GAMMA > 0:
        data = np.power(data, 1.0 / FIXED_GAMMA)

    return (data * 255).astype(np.uint8)

def detect_rice_colors(img_bgr):
    output_img = img_bgr.copy()
    h_img, w_img = output_img.shape[:2]

    # ==========================================
    # 1. 基础尺寸设置 (保持不变)
    # ==========================================
    total_box_width = 160
    total_box_height = 600
    num_sections = 4
    section_height = total_box_height // num_sections

    start_x1 = w_img // 2 - total_box_width // 2
    start_y_top = h_img // 2 - total_box_height // 2

    detected_labels = set()
    debug_info = []

    # ==========================================
    # 2. 循环处理四个小框
    # ==========================================
    for i in range(num_sections):
        x1 = start_x1
        y1 = start_y_top + (i * section_height)
        x2 = x1 + total_box_width
        y2 = y1 + section_height

        if y1 < 0: y1 = 0
        if y2 > h_img: y2 = h_img

        # 提取 ROI 并进行高斯模糊（关键步骤：减少噪点干扰）
        roi = img_bgr[y1:y2, x1:x2]
        roi_blur = cv2.GaussianBlur(roi, (5, 5), 0) 
        roi_hsv = cv2.cvtColor(roi_blur, cv2.COLOR_BGR2HSV)

        # --- 核心修改开始 ---
        
        # 1. 确定什么是“米” (去除背景)
        # 假设背景非常暗 (V < 40)，那么 V >= 40 的就是物体
        # 注意：使用形态学操作去除小白点噪点
        mask_rice_region = cv2.inRange(roi_hsv, np.array([0, 0, 40]), np.array([180, 255, 255]))
        kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (3, 3))
        mask_rice_region = cv2.morphologyEx(mask_rice_region, cv2.MORPH_OPEN, kernel)
        
        rice_pixel_count = cv2.countNonZero(mask_rice_region)
        
        current_label = None

        # 只有当米或者杂质的面积足够大时才进行判断 (例如占小框的 5%)
        box_area = (x2 - x1) * (y2 - y1)
        if rice_pixel_count > (box_area * 0.05):
            
            # 2. 定义颜色的严格范围 (HSV 掩膜)
            # 提示：OpenCV中 H范围是0-180, S是0-255, V是0-255
            
            # 【黑米判据】：亮度(V)很低，或者饱和度(S)极低且亮度不高
            # 范围：H不限, S不限, V: 40-100 (根据实际光照调整，这里设为深灰色区间)
            mask_black = cv2.inRange(roi_hsv, np.array([0, 0, 40]), np.array([180, 255, 130]))
            
            # 【黄米判据】：颜色(H)在黄色/橙色区间，且饱和度(S)较高
            # 范围：H: 10-40 (橙黄), S: > 60 (明显的颜色), V: > 100 (不能太暗)
            mask_yellow = cv2.inRange(roi_hsv, np.array([10, 110, 100]), np.array([40, 255, 255]))
            
            # 计算各颜色的像素数量（必须是在 rice_region 区域内的）
            count_black = cv2.countNonZero(cv2.bitwise_and(mask_black, mask_black, mask=mask_rice_region))
            count_yellow = cv2.countNonZero(cv2.bitwise_and(mask_yellow, mask_yellow, mask=mask_rice_region))
            
            # 3. 计算比例 (占比多少算是该颜色)
            ratio_black = count_black / rice_pixel_count
            ratio_yellow = count_yellow / rice_pixel_count
            
            # 调试信息：显示占比，方便你调整阈值
            debug_info.append(f"B{i} K:{ratio_black:.2f} Y:{ratio_yellow:.2f}")

            # 4. 判定逻辑 (优先级：黑 > 黄 > 白)
            # 如果黑色像素占比超过 20%，认为是黑头/黑米
            if ratio_black > 0.10:
                current_label = "Black"
            # 如果黄色像素占比超过 15%，认为是黄米
            elif ratio_yellow > 0.10:
                current_label = "Yellow"
            # 否则默认为白米
            else:
                current_label = "White"

            detected_labels.add(current_label)
        
        # --- 核心修改结束 ---

        # 绘图逻辑
        color_map = {"Black": (255, 0, 255), "Yellow": (0, 255, 255), "White": (255, 255, 255), None: (100,100,100)}
        draw_color = color_map.get(current_label, (100, 100, 100))
        thickness = 2 if current_label else 1
        cv2.rectangle(output_img, (x1, y1), (x2, y2), draw_color, thickness)

    # ==========================================
    # 3. 综合显示逻辑 (保持原样或微调)
    # ==========================================
    final_display_text = ""
    display_color = (255, 255, 255)

    results_to_show = []
    if "Black" in detected_labels:
        results_to_show.append("Black")
        display_color = (255, 0, 255) 
    if "Yellow" in detected_labels:
        results_to_show.append("Yellow")
        display_color = (0, 255, 255) 

    if not results_to_show:
        if "White" in detected_labels:
            final_display_text = "White"
        else:
            final_display_text = "No Rice"
            display_color = (0, 0, 255)
    else:
        final_display_text = " & ".join(results_to_show)

    # 绘制文字和外框
    cv2.rectangle(output_img, (start_x1, start_y_top), 
                  (start_x1 + total_box_width, start_y_top + total_box_height), display_color, 2)
    
    font = cv2.FONT_HERSHEY_SIMPLEX
    # 简单的文字背景板
    cv2.putText(output_img, final_display_text, (start_x1, start_y_top - 10), font, 1.0, display_color, 2)

    # 显示调试数值 (非常重要，用于现场调试)
    for idx, info in enumerate(debug_info):
        cv2.putText(output_img, info, (20, 50 + idx * 30), font, 0.6, (0, 255, 0), 1)
    
    return output_img


def run_camera_fixed():
    try:
        with TLCameraSDK() as sdk:
            cameras = sdk.discover_available_cameras()
            if not cameras:
                print("未发现相机!")
                return

            with sdk.open_camera(cameras[0]) as camera:
                # 配置硬件
                camera.exposure_time_us = EXPOSURE_TIME
                camera.frames_per_trigger_zero_for_unlimited = 0
                camera.image_poll_timeout_ms = 1000
                camera.arm(2)
                camera.issue_software_trigger()

                window_name = "ThorCam Rice Detection"
                cv2.namedWindow(window_name, cv2.WINDOW_NORMAL)
                cv2.resizeWindow(window_name, 1000, 800)

                print("相机已启动 (识别模式: 白/黄/黑)")
                print("按 'q' 键退出程序")

                while True:
                    frame = camera.get_pending_frame_or_null()
                    if frame is not None:
                        h = camera.image_height_pixels
                        w = camera.image_width_pixels
                        raw_data = np.asarray(frame.image_buffer).reshape(h, w)
                        
                        # 2. 转为彩色
                        bgr_img = cv2.cvtColor(raw_data, cv2.COLOR_BayerBG2BGR)
                        
                        # 3. 图像增强 (颜色矫正)
                        enhanced_img = apply_fixed_processing(bgr_img)

                        # 4. [修改点] 识别颜色并画框
                        final_img = detect_rice_colors(enhanced_img)

                        # 5. 显示
                        cv2.imshow(window_name, final_img)

                    if cv2.waitKey(1) & 0xFF == ord('q'):
                        break

                camera.disarm()
                cv2.destroyAllWindows()

    except Exception as e:
        print(f"运行错误: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    run_camera_fixed()

    # numba 流水线pipline 多线程工作