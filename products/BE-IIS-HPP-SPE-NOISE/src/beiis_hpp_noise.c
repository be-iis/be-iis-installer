// SPDX-License-Identifier: GPL-2.0-only
#include <linux/bitops.h>
#include <linux/bitfield.h>
#include <linux/device.h>
#include <linux/i2c.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/slab.h>

#define REG_CONTROL       0x0000
#define REG_AMPLITUDE     0x0001
#define REG_PWM_REFERENCE 0x0003
#define REG_DDS_CONTROL  0x0300
#define REG_COMPONENT_ID  0x0004
#define REG_FIRMWARE_ID   0x0005
#define COMPONENT_ID_NOISE_GENERATOR 0x4e47 /* "NG" */

/* Matches noise_generator_vhdl/src/pkg/i2c_register_pkg.vhd. */
#define CONTROL_GENERATOR     GENMASK(1, 0)
#define CONTROL_OUTPUT_ENABLE BIT(3)
#define DDS_CONTROL_ENABLE    BIT(0)
#define DDS_CONTROL_FM_ENABLE BIT(1)

struct beiis_noise {
	struct i2c_client *client;
	struct mutex lock;

	/* Updated only after a complete ACKed I2C register write. */
	u16 control;
	u16 amplitude;
	u16 pwm_reference;
	u16 dds_control;
};

static int beiis_noise_read_reg(struct i2c_client *client,
				u16 reg, u16 *value)
{
	u8 addr[2] = { reg >> 8, reg & 0xff };
	u8 data[2];
	struct i2c_msg msgs[] = {
		{
			.addr = client->addr,
			.flags = 0,
			.len = sizeof(addr),
			.buf = addr,
		},
		{
			.addr = client->addr,
			.flags = I2C_M_RD,
			.len = sizeof(data),
			.buf = data,
		},
	};
	int ret = i2c_transfer(client->adapter, msgs, ARRAY_SIZE(msgs));

	if (ret != ARRAY_SIZE(msgs))
		return ret < 0 ? ret : -EIO;

	*value = ((u16)data[0] << 8) | data[1];
	return 0;
}

static int beiis_noise_write_reg(struct i2c_client *client,
				 u16 reg, u16 value)
{
	u8 data[4] = {
		reg >> 8, reg & 0xff,
		value >> 8, value & 0xff,
	};
	int ret = i2c_master_send(client, data, sizeof(data));

	return ret == sizeof(data) ? 0 : ret < 0 ? ret : -EIO;
}

static ssize_t generator_show(struct device *dev,
			      struct device_attribute *attr, char *buf)
{
	struct beiis_noise *n = i2c_get_clientdata(to_i2c_client(dev));
	static const char * const names[] = { "null", "prn", "dds" };
	u16 control, generator;

	mutex_lock(&n->lock);
	control = n->control;
	mutex_unlock(&n->lock);
	generator = FIELD_GET(CONTROL_GENERATOR, control);
	if (generator >= ARRAY_SIZE(names))
		return -EINVAL;
	return sysfs_emit(buf, "%s\n", names[generator]);
}

static ssize_t generator_store(struct device *dev,
			       struct device_attribute *attr,
			       const char *buf, size_t count)
{
	struct beiis_noise *n = i2c_get_clientdata(to_i2c_client(dev));
	u8 value;
	u16 control;
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
	control = n->control;
	control &= ~CONTROL_GENERATOR;
	control |= FIELD_PREP(CONTROL_GENERATOR, value);
	ret = beiis_noise_write_reg(n->client, REG_CONTROL, control);
	if (!ret)
		n->control = control;
	mutex_unlock(&n->lock);
	return ret ? ret : count;
}
static DEVICE_ATTR_RW(generator);

static ssize_t output_enable_show(struct device *dev,
				  struct device_attribute *attr, char *buf)
{
	struct beiis_noise *n = i2c_get_clientdata(to_i2c_client(dev));
	u16 control;

	mutex_lock(&n->lock);
	control = n->control;
	mutex_unlock(&n->lock);
	return sysfs_emit(buf, "%u\n", !!(control & CONTROL_OUTPUT_ENABLE));
}

static ssize_t output_enable_store(struct device *dev,
				   struct device_attribute *attr,
				   const char *buf, size_t count)
{
	struct beiis_noise *n = i2c_get_clientdata(to_i2c_client(dev));
	bool value;
	u16 control;
	int ret;

	ret = kstrtobool(buf, &value);
	if (ret)
		return ret;
	mutex_lock(&n->lock);
	control = n->control;
	if (value)
		control |= CONTROL_OUTPUT_ENABLE;
	else
		control &= ~CONTROL_OUTPUT_ENABLE;
	ret = beiis_noise_write_reg(n->client, REG_CONTROL, control);
	if (!ret)
		n->control = control;
	mutex_unlock(&n->lock);
	return ret ? ret : count;
}
static DEVICE_ATTR_RW(output_enable);

static ssize_t amplitude_show(struct device *dev,
			      struct device_attribute *attr, char *buf)
{
	struct beiis_noise *n = i2c_get_clientdata(to_i2c_client(dev));
	u16 value;

	mutex_lock(&n->lock);
	value = n->amplitude;
	mutex_unlock(&n->lock);
	return sysfs_emit(buf, "%u\n", value);
}

static ssize_t amplitude_store(struct device *dev,
			       struct device_attribute *attr,
			       const char *buf, size_t count)
{
	struct beiis_noise *n = i2c_get_clientdata(to_i2c_client(dev));
	unsigned int value;
	int ret;

	ret = kstrtouint(buf, 0, &value);
	if (ret || value > 4)
		return -EINVAL;
	mutex_lock(&n->lock);
	ret = beiis_noise_write_reg(n->client, REG_AMPLITUDE, value);
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

	mutex_lock(&n->lock);
	value = n->pwm_reference;
	mutex_unlock(&n->lock);
	return sysfs_emit(buf, "%u\n", value);
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
	ret = beiis_noise_write_reg(n->client, REG_PWM_REFERENCE, value);
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
	u16 dds_control;

	mutex_lock(&n->lock);
	dds_control = n->dds_control;
	mutex_unlock(&n->lock);
	return sysfs_emit(buf, "%u\n", !!(dds_control & DDS_CONTROL_ENABLE));
}

static ssize_t dds_enable_store(struct device *dev,
				struct device_attribute *attr,
				const char *buf, size_t count)
{
	struct beiis_noise *n = i2c_get_clientdata(to_i2c_client(dev));
	bool value;
	u16 dds_control;
	int ret;

	ret = kstrtobool(buf, &value);
	if (ret)
		return ret;
	mutex_lock(&n->lock);
	dds_control = n->dds_control;
	if (value)
		dds_control |= DDS_CONTROL_ENABLE;
	else
		dds_control &= ~DDS_CONTROL_ENABLE;
	ret = beiis_noise_write_reg(n->client, REG_DDS_CONTROL, dds_control);
	if (!ret)
		n->dds_control = dds_control;
	mutex_unlock(&n->lock);
	return ret ? ret : count;
}
static DEVICE_ATTR_RW(dds_enable);

static ssize_t fm_enable_show(struct device *dev,
			      struct device_attribute *attr, char *buf)
{
	struct beiis_noise *n = i2c_get_clientdata(to_i2c_client(dev));
	u16 dds_control;

	mutex_lock(&n->lock);
	dds_control = n->dds_control;
	mutex_unlock(&n->lock);
	return sysfs_emit(buf, "%u\n", !!(dds_control & DDS_CONTROL_FM_ENABLE));
}

static ssize_t fm_enable_store(struct device *dev,
			       struct device_attribute *attr,
			       const char *buf, size_t count)
{
	struct beiis_noise *n = i2c_get_clientdata(to_i2c_client(dev));
	bool value;
	u16 dds_control;
	int ret;

	ret = kstrtobool(buf, &value);
	if (ret)
		return ret;
	mutex_lock(&n->lock);
	dds_control = n->dds_control;
	if (value)
		dds_control |= DDS_CONTROL_FM_ENABLE;
	else
		dds_control &= ~DDS_CONTROL_FM_ENABLE;
	ret = beiis_noise_write_reg(n->client, REG_DDS_CONTROL, dds_control);
	if (!ret)
		n->dds_control = dds_control;
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
	ret = beiis_noise_read_reg(n->client, REG_COMPONENT_ID, &value);
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
	ret = beiis_noise_read_reg(n->client, REG_FIRMWARE_ID, &value);
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

	/* Defaults in the VHDL image; later writes replace only ACKed values. */
	n->control = FIELD_PREP(CONTROL_GENERATOR, 1) | CONTROL_OUTPUT_ENABLE;
	n->amplitude = 0;
	n->pwm_reference = 512;
	n->dds_control = DDS_CONTROL_ENABLE | DDS_CONTROL_FM_ENABLE;

	ret = beiis_noise_read_reg(client, REG_COMPONENT_ID, &component_id);
	if (ret)
		return dev_err_probe(&client->dev, ret,
				     "failed to read component ID\n");

	if (component_id != COMPONENT_ID_NOISE_GENERATOR)
		return dev_err_probe(&client->dev, -ENODEV,
				     "unexpected component ID 0x%04x\n",
				     component_id);

	ret = beiis_noise_read_reg(client, REG_FIRMWARE_ID, &firmware_id);
	if (ret)
		return dev_err_probe(&client->dev, ret,
				     "failed to read firmware ID\n");

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
