import subprocess
import sys
import yaml

CLIENT_IP_DICT = {"TestKund1": "172.18.21.185", "TestKund2": "172.18.0.666"}

class YamlHelper:
    def __init__(self, yaml_file_path: str):
        self.yaml_file_path = yaml_file_path
        self.update_data = self.parse_yaml()
        self.client_names = [x['name'] for x in self.update_data["envFileUpdate"]["clients"]]
        self.clients = self.update_data["envFileUpdate"]["clients"]

    def parse_yaml(self):
        with open(self.yaml_file_path, "r", encoding="utf-8") as f:
            data = yaml.safe_load(f)
            return data


class EnvFileUpdate:
    def __init__(self, yaml_helper: YamlHelper):
        self.yaml_helper = yaml_helper

    @staticmethod
    def update_client_service_env_file(updates, removals, client, service):
        client_ip = CLIENT_IP_DICT[client]
        cmd = ['./edit-env.sh', '--client', client,
               '--client-ip', client_ip,
               '--skip-replace-secure-file', '--service', service]
        if updates:
            for update in updates:
                cmd.append("--env")
                cmd.append(update)
        if removals:
            for removal in removals:
                cmd.append("--remove")
                cmd.append(removal)
        subprocess.run(cmd)

    def update_env_files(self):
        clients = self.yaml_helper.clients
        for client in clients:
            client_name = client['name']
            for service in client['services']:
                service_name = service['name']
                service_edit_list = [f"{x['name']}={x['value']}" for x in service['updates']]
                service_removal_list = [x['name'] for x in service['removals']]


                self.update_client_service_env_file(service_edit_list, service_removal_list, client_name, service_name)
            subprocess.run(['./replace-secure-file.sh', '--client', client_name])



def main(path_to_yaml):
    yaml_helper = YamlHelper(path_to_yaml)
    env_files_updater = EnvFileUpdate(yaml_helper)
    env_files_updater.update_env_files()


if __name__ == "__main__":
    if len(sys.argv) > 1:
        yaml_file_path = sys.argv[1]
    else:
        print("Måste skicka in path till yaml!")
        exit(1)
    main(yaml_file_path)