import requests
import base64
import re
import urllib.parse

def decode_url_content(url):
    # 发送HTTP请求获取内容
    response = requests.get(url)
    
    # 检查请求是否成功
    if response.status_code == 200:
        # 获取响应内容
        content = response.content
        
        try:
            # 尝试用base64解码
            decoded_content = base64.b64decode(content)
            
            # 尝试将解码后的内容转换为字符串
            try:
                text = decoded_content.decode('utf-8')
                return text
            except UnicodeDecodeError:
                # 如果UTF-8解码失败，尝试其他编码
                try:
                    text = decoded_content.decode('latin-1')
                    return text
                except:
                    # 如果还是失败，返回原始的二进制数据
                    return "无法解码为文本，返回二进制数据：\n" + str(decoded_content)
        except:
            return "内容解码失败，可能不是有效的base64编码"
    else:
        return f"请求失败，状态码: {response.status_code}"

def convert_trojan_to_forward(trojan_line):
    # 分离链接和备注
    if '#' in trojan_line:
        trojan_url, remark = trojan_line.split('#', 1)
        remark = '#' + remark
    else:
        trojan_url = trojan_line
        remark = ''
    
    # 使用正则表达式提取trojan链接中的各个部分
    pattern = r'trojan://([^@]+)@([^:]+):(\d+)\?(.*)'
    match = re.match(pattern, trojan_url)
    
    if match:
        password = match.group(1)
        server = match.group(2)
        port = match.group(3)
        params_str = match.group(4)
        
        # 创建新的forward格式
        new_url = f"forward=trojan://{password}@{server}:{port}?serverName={server}&skipVerify=true"
        
        # 添加备注（如果有）
        result = new_url + remark
        
        return result
    else:
        return "格式错误: " + trojan_line

def process_multiple_lines(content):
    lines = content.strip().split('\n')
    converted_lines = []
    
    for line in lines:
        if line.strip().startswith('trojan://'):
            converted_line = convert_trojan_to_forward(line.strip())
            converted_lines.append(converted_line)
        else:
            converted_lines.append(line)  # 保留非trojan行
    
    return '\n'.join(converted_lines)

def main():
    # 用户输入URL
    url = input("请输入URL地址: ")
    
    # 获取并解码内容
    decoded_content = decode_url_content(url)
    
    if decoded_content.startswith("请求失败") or decoded_content.startswith("内容解码失败") or decoded_content.startswith("无法解码为文本"):
        print(decoded_content)
        return
    
    # 处理解码后的内容
    converted_content = process_multiple_lines(decoded_content)
    
    # 输出转换后的内容
    print("\n转换后的内容:")
    print(converted_content)
    
    # 保存到文件
    save = input("\n是否保存到文件? (y/n): ")
    if save.lower() == 'y':
        filename = input("请输入文件名: ")
        with open(filename, 'w', encoding='utf-8') as f:
            f.write(converted_content)
        print(f"内容已保存到文件: {filename}")

# 运行主函数
if __name__ == "__main__":
    main()