// SPDX-License-Identifier: GPL-2.0-only
#include <linux/bitops.h>
#include <linux/device.h>
#include <linux/i2c.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/slab.h>

#define REG_CONTROL       0x0000
#define REG_DIF_GAIN      0x0001
#define REG_REF_PWM       0x0003
#define REG_COMPONENT_ID  0x0004
#define REG_FIRMWARE_ID   0x0005
#define REG_DDS_CONTROL   0x0300

#define COMPONENT_ID_NOISE_GENERATOR 0x4e47 /* "NG" */

struct beiis_noise {
	struct i2c_client *client;
	struct mutex lock;
	u8 generator, amplitude;
	bool output_enable, dds_enable, fm_enable;
	u16 pwm_reference;
};

static int read_reg(struct beiis_noise *n, u16 reg, u16 *value)
{
	u8 address[] = { reg >> 8, reg };
	u8 data[2];
	struct i2c_msg messages[] = {
		{
			.addr = n->client->addr,
			.flags = 0,
			.len = sizeof(address),
			.buf = address,
		},
		{
			.addr = n->client->addr,
			.flags = I2C_M_RD,
			.len = sizeof(data),
			.buf = data,
		},
	};
	int ret;

	ret = i2c_transfer(n->client->adapter, messages, ARRAY_SIZE(messages));
	if (ret == ARRAY_SIZE(messages)) {
		*value = ((u16)data[0] << 8) | data[1];
		return 0;
	}

	return ret < 0 ? ret : -EIO;
}

static int write_reg(struct beiis_noise *n, u16 reg, u16 value)
{
	u8 data[] = { reg >> 8, reg, value >> 8, value };
	int ret = i2c_master_send(n->client, data, sizeof(data));

	return ret == sizeof(data) ? 0 : ret < 0 ? ret : -EIO;
}

static int read_control(struct beiis_noise *n)
{
	u16 value;
	int ret = read_reg(n, REG_CONTROL, &value);

	if (!ret) {
		n->generator = value & GENMASK(1, 0);
		n->output_enable = !!(value & BIT(3));
	}

	return ret;
}

static int read_dds_control(struct beiis_noise *n)
{
	u16 value;
	int ret = read_reg(n, REG_DDS_CONTROL, &value);

	if (!ret) {
		n->dds_enable = !!(value & BIT(0));
		n->fm_enable = !!(value & BIT(1));
	}

	return ret;
}

static int write_control(struct beiis_noise *n)
{
	return write_reg(n, REG_CONTROL,
			 n->generator | (n->output_enable ? BIT(3) : 0));
}

static int write_dds_control(struct beiis_noise *n)
{
	return write_reg(n, REG_DDS_CONTROL,
			 (n->dds_enable ? BIT(0) : 0) |
			 (n->fm_enable ? BIT(1) : 0));
}

static ssize_t generator_show(struct device *dev,
			      struct device_attribute *attr, char *buf)
{
	struct beiis_noise *n = i2c_get_clientdata(to_i2c_client(dev));
	static const char * const names[] = { "null", "prn", "dds" };
	int ret;

	mutex_lock(&n->lock);
	ret = read_control(n);
	if (!ret && n->generator >= ARRAY_SIZE(names))
		ret = -EINVAL;
	if (!ret)
		ret = sysfs_emit(buf, "%s\n", names[n->generator]);
	mutex_unlock(&n->lock);

	return ret;
}

static ssize_t generator_store(struct device *dev,
			       struct device_attribute *attr,
			       const char *buf, size_t count)
{
	struct beiis_noise *n = i2c_get_clientdata(to_i2c_client(dev));
	u8 value;
	int ret;

	if (sysfs_streq(buf, "null"))
		value = 0;
	else if (sysfs_streq(buf, "prn"))
		value = 1;
	else if (sysfs_streq(buf, "dds"))
		value = 2;
	else
		return -EINVAL;

	mutex_lock(&n->lock);
	n->generator = value;
	ret = write_control(n);
	mutex_unlock(&n->lock);

	return ret ? ret : count;
}
static DEVICE_ATTR_RW(generator);

static ssize_t output_enable_show(struct device *dev,
				  struct device_attribute *attr, char *buf)
{
	struct beiis_noise *n = i2c_get_clientdata(to_i2c_client(dev));
	int ret;

	mutex_lock(&n->lock);
	ret = read_control(n);
	if (!ret)
		ret = sysfs_emit(buf, "%u\n", n->output_enable);
	mutex_unlock(&n->lock);

	return ret;
}

static ssize_t output_enable_store(struct device *dev,
				   struct device_attribute *attr,
				   const char *buf, size_t count)
{
	struct beiis_noise *n = i2c_get_clientdata(to_i2c_client(dev));
	bool value;
	int ret;

	ret = kstrtobool(buf, &value);
	if (ret)
		return ret;

	mutex_lock(&n->lock);
	n->output_enable = value;
	ret = write_control(n);
	mutex_unlock(&n->lock);

	return ret ? ret : count;
}
static DEVICE_ATTR_RW(output_enable);

static ssize_t amplitude_show(struct device *dev,
			      struct device_attribute *attr, char *buf)
{
	struct beiis_noise *n = i2c_get_clientdata(to_i2c_client(dev));
	u16 value;
	int ret;

	mutex_lock(&n->lock);
	ret = read_reg(n, REG_DIF_GAIN, &value);
	if (!ret) {
		n->amplitude = value & 0xff;
		ret = sysfs_emit(buf, "%u\n", n->amplitude);
	}
	mutex_unlock(&n->lock);

	return ret;
}

static ssize_t amplitude_store(struct device *dev,
			       struct device_attribute *attr,
			       const char *buf, size_t count)
{
	struct beiis_noise *n = i2c_get_clientdata(to_i2c_client(dev));
	unsigned int value;
	int ret;

	ret = kstrtouint(buf, 0, &value);
	if (ret || value > 255)
		return -EINVAL;

	mutex_lock(&n->lock);
	ret = write_reg(n, REG_DIF_GAIN, value);
	if (!ret)
		n->amplitude = value;
	mutex_unlock(&n->lock);

	return ret ? ret : count;
}
static DEVICE_ATTR_RW(amplitude);

static ssize_t pwm_reference_show(struct device *dev,
				  struct device_attribute *attr, char *buf)
{
	struct beiis_noise *n = i2c_get_clientdata(to_i2c_client(dev));
	u16 value;
	int ret;

	mutex_lock(&n->lock);
	ret = read_reg(n, REG_REF_PWM, &value);
	if (!ret) {
		n->pwm_reference = value & 0x03ff;
		ret = sysfs_emit(buf, "%u\n", n->pwm_reference);
	}
	mutex_unlock(&n->lock);

	return ret;
}

static ssize_t pwm_reference_store(struct device *dev,
				   struct device_attribute *attr,
				   const char *buf, size_t count)
{
	struct beiis_noise *n = i2c_get_clientdata(to_i2c_client(dev));
	unsigned int value;
	int ret;

	ret = kstrtouint(buf, 0, &value);
	if (ret || value > 1023)
		return -EINVAL;

	mutex_lock(&n->lock);
	ret = write_reg(n, REG_REF_PWM, value);
	if (!ret)
		n->pwm_reference = value;
	mutex_unlock(&n->lock);

	return ret ? ret : count;
}
static DEVICE_ATTR_RW(pwm_reference);

static ssize_t dds_enable_show(struct device *dev,
			       struct device_attribute *attr, char *buf)
{
	struct beiis_noise *n = i2c_get_clientdata(to_i2c_client(dev));
	int ret;

	mutex_lock(&n->lock);
	ret = read_dds_control(n);
	if (!ret)
		ret = sysfs_emit(buf, "%u\n", n->dds_enable);
	mutex_unlock(&n->lock);

	return ret;
}

static ssize_t dds_enable_store(struct device *dev,
				struct device_attribute *attr,
				const char *buf, size_t count)
{
	struct beiis_noise *n = i2c_get_clientdata(to_i2c_client(dev));
	bool value;
	int ret;

	ret = kstrtobool(buf, &value);
	if (ret)
		return ret;

	mutex_lock(&n->lock);
	n->dds_enable = value;
	ret = write_dds_control(n);
	mutex_unlock(&n->lock);

	return ret ? ret : count;
}
static DEVICE_ATTR_RW(dds_enable);

static ssize_t fm_enable_show(struct device *dev,
			      struct device_attribute *attr, char *buf)
{
	struct beiis_noise *n = i2c_get_clientdata(to_i2c_client(dev));
	int ret;

	mutex_lock(&n->lock);
	ret = read_dds_control(n);
	if (!ret)
		ret = sysfs_emit(buf, "%u\n", n->fm_enable);
	mutex_unlock(&n->lock);

	return ret;
}

static ssize_t fm_enable_store(struct device *dev,
			       struct device_attribute *attr,
			       const char *buf, size_t count)
{
	struct beiis_noise *n = i2c_get_clientdata(to_i2c_client(dev));
	bool value;
	int ret;

	ret = kstrtobool(buf, &value);
	if (ret)
		return ret;

	mutex_lock(&n->lock);
	n->fm_enable = value;
	ret = write_dds_control(n);
	mutex_unlock(&n->lock);

	return ret ? ret : count;
}
static DEVICE_ATTR_RW(fm_enable);

static ssize_t component_id_show(struct device *dev,
				 struct device_attribute *attr, char *buf)
{
	struct beiis_noise *n = i2c_get_clientdata(to_i2c_client(dev));
	u16 value;
	int ret;

	mutex_lock(&n->lock);
	ret = read_reg(n, REG_COMPONENT_ID, &value);
	if (!ret)
		ret = sysfs_emit(buf, "0x%04x\n", value);
	mutex_unlock(&n->lock);

	return ret;
}
static DEVICE_ATTR_RO(component_id);

static ssize_t firmware_id_show(struct device *dev,
				struct device_attribute *attr, char *buf)
{
	struct beiis_noise *n = i2c_get_clientdata(to_i2c_client(dev));
	u16 value;
	int ret;

	mutex_lock(&n->lock);
	ret = read_reg(n, REG_FIRMWARE_ID, &value);
	if (!ret)
		ret = sysfs_emit(buf, "0x%04x\n", value);
	mutex_unlock(&n->lock);

	return ret;
}
static DEVICE_ATTR_RO(firmware_id);

static struct attribute *beiis_noise_attrs[] = {
	&dev_attr_generator.attr,
	&dev_attr_output_enable.attr,
	&dev_attr_amplitude.attr,
	&dev_attr_pwm_reference.attr,
	&dev_attr_dds_enable.attr,
	&dev_attr_fm_enable.attr,
	&dev_attr_component_id.attr,
	&dev_attr_firmware_id.attr,
	NULL,
};
ATTRIBUTE_GROUPS(beiis_noise);

static int beiis_noise_probe(struct i2c_client *client)
{
	struct beiis_noise *n;
	u16 component_id, firmware_id;
	int ret;

	n = devm_kzalloc(&client->dev, sizeof(*n), GFP_KERNEL);
	if (!n)
		return -ENOMEM;

	n->client = client;
	mutex_init(&n->lock);
	i2c_set_clientdata(client, n);

	ret = read_reg(n, REG_COMPONENT_ID, &component_id);
	if (ret)
		return dev_err_probe(&client->dev, ret,
				     "failed to read component ID\n");

	if (component_id != COMPONENT_ID_NOISE_GENERATOR)
		return dev_err_probe(&client->dev, -ENODEV,
				     "unexpected component ID 0x%04x\n",
				     component_id);

	ret = read_reg(n, REG_FIRMWARE_ID, &firmware_id);
	if (ret)
		return dev_err_probe(&client->dev, ret,
				     "failed to read firmware ID\n");

	mutex_lock(&n->lock);
	ret = read_control(n);
	if (!ret)
		ret = read_reg(n, REG_DIF_GAIN, &component_id);
	if (!ret)
		n->amplitude = component_id & 0xff;
	if (!ret)
		ret = read_reg(n, REG_REF_PWM, &component_id);
	if (!ret)
		n->pwm_reference = component_id & 0x03ff;
	if (!ret)
		ret = read_dds_control(n);
	mutex_unlock(&n->lock);
	if (ret)
		return dev_err_probe(&client->dev, ret,
				     "failed to read initial configuration\n");

	dev_info(&client->dev, "detected Noise Generator (firmware 0x%04x)\n",
		 firmware_id);
	return 0;
}

static const struct of_device_id match[] = {
	{ .compatible = "be-iis,hpp-spe-noise" }, { }
};
MODULE_DEVICE_TABLE(of, match);

static struct i2c_driver beiis_noise_driver = {
	.driver = {
		.name = "beiis-hpp-spe-noise",
		.of_match_table = match,
		.dev_groups = beiis_noise_groups,
	},
	.probe = beiis_noise_probe,
};
module_i2c_driver(beiis_noise_driver);

MODULE_AUTHOR("Brechel Electronic");
MODULE_DESCRIPTION("BE-IIS HPP SPE NOISE control driver");
MODULE_LICENSE("GPL");
